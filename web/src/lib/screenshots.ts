import { readdir } from "node:fs/promises";
import path from "node:path";

export type Screenshot = {
  src: string;
  caption: string;
};

const IMAGE_EXTENSIONS = new Set([".png", ".jpg", ".jpeg", ".webp", ".avif"]);

/**
 * Lists whatever is in `public/screenshots` at build time. Dropping a file into
 * that folder and redeploying is all it takes to add a shot — no code edit, no
 * manifest to keep in sync.
 *
 * Filenames become captions: `02-clipboard-tray.png` renders as "Clipboard tray".
 * A leading number is only there to control ordering and is stripped.
 */
export async function getScreenshots(): Promise<Screenshot[]> {
  const directory = path.join(process.cwd(), "public", "screenshots");

  let entries: string[];
  try {
    entries = await readdir(directory);
  } catch {
    return [];
  }

  return entries
    .filter((name) => IMAGE_EXTENSIONS.has(path.extname(name).toLowerCase()))
    .sort((a, b) => a.localeCompare(b, "en", { numeric: true }))
    .map((name) => ({
      src: `/screenshots/${name}`,
      caption: toCaption(name),
    }));
}

/**
 * Finds the shot for one tab: `public/screenshots/tabs/<slug>.<ext>`, any of the
 * supported extensions. Returns null so the tab section can fall back to a
 * placeholder instead of rendering a broken image.
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

function toCaption(filename: string): string {
  const base = path
    .basename(filename, path.extname(filename))
    .replace(/^\d+[-_.\s]*/, "")
    .replace(/[-_]+/g, " ")
    .trim();

  if (base.length === 0) return "Monotch";
  return base.charAt(0).toUpperCase() + base.slice(1);
}
