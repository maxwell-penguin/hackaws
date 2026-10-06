export const RECIPE_CATEGORIES = {
  "use-it-up": "Build around the items with the fewest days left.",
  healthy:
    "Balanced and mostly whole foods: plenty of vegetables, lean protein or legumes, whole grains. No deep-frying and no heavy cream or butter sauces.",
  "sugar-free":
    "No added sugar: no sugar, honey, maple syrup, jam, or sweetened yogurt and sauces. Naturally occurring sugar in whole fruit and plain dairy is fine. If the familiar version of the dish normally has added sugar, say in the summary what replaces it.",
  "high-protein": "At least 25 g of protein per serving, from whole-food sources.",
  "low-carb":
    "About 25 g of carbohydrate or less per serving. No pasta, rice, bread, or potatoes unless a low-carb substitute is named.",
  vegetarian: "No meat, poultry, or fish. Eggs and dairy are fine.",
  vegan: "No animal products at all: no meat, fish, eggs, dairy, or honey.",
  "gluten-free":
    'No wheat, barley, rye, regular pasta, bread, couscous, or soy sauce. Where a gluten-free version is needed, name it in the ingredient (for example "gluten-free pasta").',
  "dairy-free":
    "No milk, cheese, butter, yogurt, cream, or whey. Name dairy-free substitutes explicitly.",
  comfort: "Hearty, warm, satisfying food.",
  light: "Light and fresh: salads, bowls, and cold or quick-cooked dishes.",
  sweet: "Something sweet: a dessert, a sweet breakfast, or a sweet snack.",
  snack: "A small snack or bite, ready in about 10 minutes or less.",
  quick: "Ready in 20 minutes or less, start to finish.",
} as const;

export type RecipeCategory = keyof typeof RECIPE_CATEGORIES;

export const RECIPE_CATEGORY_KEYS = Object.keys(RECIPE_CATEGORIES) as RecipeCategory[];

export function isRecipeCategory(value: unknown): value is RecipeCategory {
  return typeof value === "string" && Object.hasOwn(RECIPE_CATEGORIES, value);
}
