import type { Metadata } from "next";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Licence agreement",
  description: `End User Licence Agreement for ${site.name}.`,
};

/**
 * Read from the repository's LICENSE at build time so the site and the app can
 * never disagree about the terms. Falls back to a pointer if the web folder is
 * ever deployed on its own.
 */
async function loadEula(): Promise<string | null> {
  try {
    return await readFile(path.join(process.cwd(), "..", "LICENSE"), "utf8");
  } catch {
    return null;
  }
}

export default async function EulaPage() {
  const eula = await loadEula();

  return (
    <section className="mx-auto max-w-3xl px-5 py-20">
      <h1 className="font-display text-4xl font-semibold tracking-tight">
        End User Licence Agreement
      </h1>

      <div className="sticker mt-10 rounded-card bg-surface p-8">
        {eula ? (
          <pre className="overflow-x-auto text-sm leading-relaxed whitespace-pre-wrap">
            {eula}
          </pre>
        ) : (
          <p className="leading-relaxed text-ink-soft">
            The agreement ships inside the app under Help → End User Licence
            Agreement. For a copy, email{" "}
            <a href={`mailto:${site.email}`} className="font-semibold text-ink underline">
              {site.email}
            </a>
            .
          </p>
        )}
      </div>

      <p className="mt-6 text-sm text-ink-soft">
        Note: the bundled agreement was written for App Store distribution. It
        needs revising for direct sale before you take payments.
      </p>
    </section>
  );
}
