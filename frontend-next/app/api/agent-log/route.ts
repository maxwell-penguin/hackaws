import { readFile } from "fs/promises";
import path from "path";

// process.cwd() is frontend-next/ (where `next dev`/`next start` runs from) — the repo
// root, and agent-service/, are one level up.
const REPO_ROOT = path.resolve(process.cwd(), "..");

export async function GET(request: Request) {
  const logPath = path.resolve(
    REPO_ROOT,
    process.env.AGENT_LOG_PATH ?? "agent-service/agent.log",
  );

  const limit = Number(new URL(request.url).searchParams.get("limit")) || 20;

  let raw: string;
  try {
    raw = await readFile(logPath, "utf-8");
  } catch (err: unknown) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      return Response.json([]);
    }
    throw err;
  }

  const entries = raw
    .split("\n")
    .filter((line) => line.trim())
    .slice(-limit)
    .reverse()
    .flatMap((line) => {
      try {
        return [JSON.parse(line)];
      } catch {
        return [];
      }
    });

  return Response.json(entries);
}
