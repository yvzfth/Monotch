import { readdir } from "node:fs/promises";
import path from "node:path";

const IMAGE_EXTENSIONS = new Set([".png", ".jpg", ".jpeg", ".webp", ".avif"]);

/**
 * Finds the shot for one tab: `public/screenshots/tabs/<slug>.<ext>`, in any of
 * the supported formats. Resolved at build time, so adding a screenshot is a
 * matter of dropping the file in and redeploying — there is no manifest to edit.
 *
 * Returns null when nothing matches, letting the tab section fall back to a
 * placeholder rather than rendering a broken image.
 */
export async function getTabScreenshot(slug: string): Promise<string | null> {
  const directory = path.join(process.cwd(), "public", "screenshots", "tabs");

  let entries: string[];
  try {
    entries = await readdir(directory);
  } catch {
    return null;
  }

  const match = entries.find(
    (name) =>
      path.basename(name, path.extname(name)).toLowerCase() === slug &&
      IMAGE_EXTENSIONS.has(path.extname(name).toLowerCase()),
  );

  return match ? `/screenshots/tabs/${match}` : null;
}
