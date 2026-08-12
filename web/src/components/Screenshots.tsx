import Image from "next/image";
import Reveal from "./Reveal";
import { getScreenshots } from "@/lib/screenshots";

const PLACEHOLDER_HINT = [
  "Media tab with lyrics",
  "Clipboard tray",
  "System vitals",
  "Camera preview",
];

export default async function Screenshots() {
  const shots = await getScreenshots();

  return (
    <section
      id="screenshots"
      className="border-y-2 border-ink/10 bg-paper-deep"
    >
      <div className="mx-auto max-w-6xl scroll-mt-24 px-5 py-24">
        <Reveal>
          <div className="max-w-2xl">
            <h2 className="font-display text-4xl font-semibold tracking-tight sm:text-5xl">
              See it on a real desktop.
            </h2>
            <p className="mt-5 text-lg leading-relaxed text-ink-soft">
              The island expands under the notch, does its job, and collapses back
              out of the way.
            </p>
          </div>
        </Reveal>

        {shots.length > 0 ? (
          <div className="mt-14 grid gap-6 sm:grid-cols-2">
            {shots.map((shot, index) => (
              <Reveal key={shot.src} delay={(index % 2) * 90}>
              <figure className="sticker rounded-card bg-surface p-3">
                <div className="relative aspect-16/10 overflow-hidden rounded-[1.25rem] bg-ink/5">
                  <Image
                    src={shot.src}
                    alt={shot.caption}
                    fill
                    sizes="(min-width: 640px) 50vw, 100vw"
                    className="object-cover"
                    priority={index < 2}
                  />
                </div>
                <figcaption className="px-3 py-3 text-sm font-medium text-ink-soft">
                  {shot.caption}
                </figcaption>
              </figure>
              </Reveal>
            ))}
          </div>
        ) : (
          <div className="mt-14 grid gap-6 sm:grid-cols-2">
            {PLACEHOLDER_HINT.map((label) => (
              <div
                key={label}
                className="grid aspect-16/10 place-items-center rounded-card border-2 border-dashed border-ink/25 bg-surface/50 p-6 text-center"
              >
                <div>
                  <p className="font-display text-lg font-semibold">{label}</p>
                  <p className="mt-2 text-sm text-ink-soft">
                    Drop a screenshot into{" "}
                    <code className="rounded bg-paper-deep px-1.5 py-0.5 font-mono text-xs">
                      web/public/screenshots/
                    </code>
                  </p>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}
