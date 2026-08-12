import type { Metadata } from "next";
import Link from "next/link";
import { downloadUrl, site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Download",
  description: `Download ${site.name} for macOS.`,
};

const steps = [
  {
    title: "Open the disk image",
    body: "Double-click the downloaded .dmg and drag Monotch into your Applications folder.",
  },
  {
    title: "Launch it once",
    body: "macOS checks the signature the first time you open it. Monotch is signed and notarised by Apple, so no right-click workaround is needed.",
  },
  {
    title: "Grant what you use",
    body: "Camera, Accessibility and Automation permissions are only asked for when you first open the feature that needs them.",
  },
];

export default function DownloadPage() {
  const hasBuild = downloadUrl !== "/download";

  return (
    <>
      <section className="border-b-2 border-ink/10 bg-paper-deep">
        <div className="mx-auto max-w-3xl px-5 py-20 text-center">
          <h1 className="font-display text-5xl font-semibold tracking-tight">
            Download Monotch
          </h1>
          <p className="mx-auto mt-5 max-w-lg text-lg leading-relaxed text-ink-soft">
            Free to use for media controls. Upgrade in-app whenever you want the
            rest.
          </p>

          {hasBuild ? (
            <a
              href={downloadUrl}
              className="sticker sticker-press mt-9 inline-block rounded-full bg-lemon px-8 py-4 text-lg font-semibold text-on-accent"
            >
              Download .dmg
            </a>
          ) : (
            <p className="sticker mx-auto mt-9 max-w-md rounded-card bg-surface px-6 py-5 text-sm leading-relaxed">
              No build is published yet. Set{" "}
              <code className="rounded bg-paper-deep px-1.5 py-0.5 font-mono text-xs">
                NEXT_PUBLIC_DOWNLOAD_URL
              </code>{" "}
              in your Vercel project to the release .dmg and this becomes a live
              download button.
            </p>
          )}

          <p className="mt-5 text-sm text-ink-soft">{site.requirements}</p>
        </div>
      </section>

      <section className="mx-auto max-w-3xl px-5 py-20">
        <h2 className="font-display text-3xl font-semibold tracking-tight">
          Installing
        </h2>

        <ol className="mt-10 space-y-4">
          {steps.map((step, index) => (
            <li key={step.title} className="sticker flex gap-5 rounded-card bg-surface p-6">
              <span className="sticker-sm grid h-9 w-9 shrink-0 place-items-center rounded-full bg-lemon font-bold text-on-accent">
                {index + 1}
              </span>
              <div>
                <h3 className="font-display text-lg font-semibold">{step.title}</h3>
                <p className="mt-1.5 leading-relaxed text-ink-soft">{step.body}</p>
              </div>
            </li>
          ))}
        </ol>

        <p className="mt-10 text-sm text-ink-soft">
          Something not working?{" "}
          <a href={`mailto:${site.email}`} className="font-semibold text-ink underline">
            Email me
          </a>{" "}
          or read the{" "}
          <Link href="/pricing" className="font-semibold text-ink underline">
            licence details
          </Link>
          .
        </p>
      </section>
    </>
  );
}
