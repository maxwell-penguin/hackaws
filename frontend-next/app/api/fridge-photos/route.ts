import Anthropic from "@anthropic-ai/sdk";
import { stripJsonFences } from "../../lib/strict-json";
import { strapiHeaders } from "../../lib/strapi";

const anthropic = new Anthropic();

const ALLOWED_MEDIA_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/gif",
  "image/webp",
]);

const STAPLE_STATES = new Set(["present", "absent", "unclear"]);
const PRODUCE_STATES = new Set(["fresh", "aging", "spoiled", "unclear"]);

type StrapiItem = {
  documentId: string;
  name: string;
  isStaple: boolean;
  isProduce: boolean;
};

function buildPrompt(staples: StrapiItem[], produce: StrapiItem[]): string {
  const stapleList = staples.map((i) => `- ${i.name}`).join("\n") || "(none)";
  const produceList = produce.map((i) => `- ${i.name}`).join("\n") || "(none)";

  return `You are looking at a photo of the inside of a refrigerator/pantry zone.

Staple items to check for presence — is each clearly visible in the photo?
${stapleList}

Produce items to check for freshness — look for visible signs like browning, wilting, or mold.
${produceList}

Return STRICT JSON only — no markdown, no code fences, no commentary — in exactly this shape:
{
  "staples": { "<exact item name>": "present" | "absent" | "unclear", ... },
  "produce": { "<exact item name>": "fresh" | "aging" | "spoiled" | "unclear", ... }
}

Include every item listed above as a key, using the exact name given. Use "unclear" whenever the photo doesn't give you enough to be sure — do not guess. If a section has no items listed, return an empty object for it.`;
}

function normalizeSection(
  section: unknown,
  allowed: Set<string>,
): Record<string, string> {
  if (!section || typeof section !== "object") return {};
  const result: Record<string, string> = {};
  for (const [name, value] of Object.entries(section as Record<string, unknown>)) {
    if (typeof value === "string" && allowed.has(value)) {
      result[name.trim().toLowerCase()] = value;
    }
  }
  return result;
}

export async function POST(request: Request) {
  const strapiUrl = process.env.STRAPI_URL;
  if (!strapiUrl) {
    return Response.json({ error: "STRAPI_URL is not configured" }, { status: 500 });
  }

  const formData = await request.formData();
  const image = formData.get("image");
  const zoneId = formData.get("zoneId");
  if (!(image instanceof Blob)) {
    return Response.json({ error: "Missing 'image' file in form data" }, { status: 400 });
  }
  if (typeof zoneId !== "string" || !zoneId) {
    return Response.json({ error: "Missing 'zoneId' field in form data" }, { status: 400 });
  }

  const itemsResponse = await fetch(
    `${strapiUrl}/api/items?filters[fridgeZone][$eq]=${encodeURIComponent(zoneId)}&filters[status][$eq]=active&pagination[pageSize]=100`,
    { headers: strapiHeaders() },
  );
  if (!itemsResponse.ok) {
    const body = await itemsResponse.text();
    return Response.json(
      { error: `Failed to fetch items from Strapi (${itemsResponse.status}): ${body}` },
      { status: 502 },
    );
  }
  const { data: items } = (await itemsResponse.json()) as { data: StrapiItem[] };

  const staples = items.filter((i) => i.isStaple);
  const produce = items.filter((i) => i.isProduce);

  // Upload the photo before spending on the vision call, so an upload failure fails fast.
  const uploadForm = new FormData();
  uploadForm.append("files", image);
  const uploadResponse = await fetch(`${strapiUrl}/api/upload`, {
    method: "POST",
    headers: process.env.STRAPI_API_TOKEN
      ? { Authorization: `Bearer ${process.env.STRAPI_API_TOKEN}` }
      : undefined,
    body: uploadForm,
  });
  if (!uploadResponse.ok) {
    const body = await uploadResponse.text();
    return Response.json(
      { error: `Failed to upload photo to Strapi (${uploadResponse.status}): ${body}` },
      { status: 502 },
    );
  }
  const [uploadedFile] = (await uploadResponse.json()) as Array<{ url: string }>;
  const photoUrl = uploadedFile.url.startsWith("/")
    ? `${strapiUrl}${uploadedFile.url}`
    : uploadedFile.url;

  let rawText = "";
  let staplesResult: Record<string, string> = {};
  let produceResult: Record<string, string> = {};

  if (staples.length > 0 || produce.length > 0) {
    const mediaType = ALLOWED_MEDIA_TYPES.has(image.type) ? image.type : "image/jpeg";
    const imageData = Buffer.from(await image.arrayBuffer()).toString("base64");

    const response = await anthropic.messages.create({
      model: "claude-sonnet-4-6",
      max_tokens: 2048,
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image",
              source: { type: "base64", media_type: mediaType as any, data: imageData },
            },
            { type: "text", text: buildPrompt(staples, produce) },
          ],
        },
      ],
    });

    const textBlock = response.content.find((block) => block.type === "text");
    rawText = textBlock?.text ?? "";
    console.log(`[fridge-photos] zoneId=${zoneId} raw Claude response:`, rawText);

    try {
      const parsed = JSON.parse(stripJsonFences(rawText));
      staplesResult = normalizeSection(parsed?.staples, STAPLE_STATES);
      produceResult = normalizeSection(parsed?.produce, PRODUCE_STATES);
    } catch {
      // Leave both empty — every item below falls through to "unclear".
    }
  }

  const flaggedDocumentIds: string[] = [];

  const updated = await Promise.all(
    items.map(async (item) => {
      const key = item.name.trim().toLowerCase();
      const data: Record<string, string> = {};

      if (item.isStaple) {
        const state = staplesResult[key];
        if (state === "present") data.status = "active";
        else if (state === "absent") data.status = "depleted";
        data.visionConfidence = state === "present" || state === "absent" ? "confirmed" : "unclear";
      } else if (item.isProduce) {
        const state = produceResult[key];
        if (state === "fresh" || state === "aging" || state === "spoiled") {
          data.freshnessState = state;
        }
        data.visionConfidence =
          state === "fresh" || state === "aging" || state === "spoiled" ? "confirmed" : "unclear";
      } else {
        return null;
      }

      if (data.status || data.freshnessState || data.visionConfidence === "unclear") {
        flaggedDocumentIds.push(item.documentId);
      }

      const strapiResponse = await fetch(`${strapiUrl}/api/items/${item.documentId}`, {
        method: "PUT",
        headers: strapiHeaders(),
        body: JSON.stringify({ data }),
      });
      if (!strapiResponse.ok) {
        const body = await strapiResponse.text();
        throw new Error(`Strapi update failed for ${item.name} (${strapiResponse.status}): ${body}`);
      }
      const { data: updatedItem } = await strapiResponse.json();
      return updatedItem;
    }),
  );

  const deltaEventResponse = await fetch(`${strapiUrl}/api/delta-events`, {
    method: "POST",
    headers: strapiHeaders(),
    body: JSON.stringify({
      data: {
        photoUrl,
        zoneId,
        timestamp: new Date().toISOString(),
        geminiRawResponse: rawText,
        itemsFlagged: flaggedDocumentIds,
      },
    }),
  });
  if (!deltaEventResponse.ok) {
    const body = await deltaEventResponse.text();
    return Response.json(
      { error: `Failed to create DeltaEvent (${deltaEventResponse.status}): ${body}` },
      { status: 502 },
    );
  }
  const { data: deltaEvent } = await deltaEventResponse.json();

  return Response.json({
    items: updated.filter(Boolean),
    deltaEvent,
    rawResponse: rawText,
  });
}
