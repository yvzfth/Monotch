import Image from "next/image";
import FeatureIcon from "./FeatureIcon";
import Reveal from "./Reveal";
import { getTabScreenshot } from "@/lib/screenshots";
import { tabs, type Tab } from "@/lib/site";

async function TabRow({ tab, index }: { tab: Tab; index: number }) {
  const shot = await getTabScreenshot(tab.slug);
  const imageFirst = index % 2 === 1;

  return (
    <Reveal>
      <article className="grid items-center gap-10 lg:grid-cols-2 lg:gap-16">
        <div className={imageFirst ? "lg:order-2" : undefined}>
          <div className="flex items-center gap-3">
            <span
              className={`sticker-sm grid h-11 w-11 place-items-center rounded-xl ${tab.accent} text-on-accent`}
            >
              <FeatureIcon name={tab.icon} className="h-5 w-5" />
            </span>
            <span className="text-sm font-bold tracking-widest uppercase text-ink-soft">
              {tab.name} tab
            </span>
          </div>

          <h3 className="mt-6 font-display text-3xl leading-tight font-semibold tracking-tight sm:text-4xl">
            {tab.headline}
          </h3>

          <p className="mt-4 text-lg leading-relaxed text-ink-soft">{tab.body}</p>

          <ul className="mt-7 space-y-3">
            {tab.points.map((point) => (
              <li key={point} className="flex items-start gap-3">
                <span
                  className={`mt-1.5 h-2.5 w-2.5 shrink-0 rounded-full ${tab.accent}`}
                  aria-hidden
                />
                <span className="leading-relaxed">{point}</span>
              </li>
            ))}
          </ul>
        </div>

        <figure className={imageFirst ? "lg:order-1" : undefined}>
          {shot ? (
            <div className="sticker rounded-card bg-surface p-3">
              <div className="relative aspect-16/10 overflow-hidden rounded-[1.25rem] bg-ink/5">
                <Image
                  src={shot}
                  alt={`The ${tab.name} tab of Monotch`}
                  fill
                  sizes="(min-width: 1024px) 50vw, 100vw"
                  className="object-cover"
                />
              </div>
            </div>
          ) : (
            <div
              className={`grid aspect-16/10 place-items-center rounded-card border-2 border-dashed border-ink/25 ${tab.accent}/10 p-8 text-center`}
            >
              <div>
                <p className="font-display text-lg font-semibold">
                  {tab.name} tab screenshot
                </p>
                <p className="mt-2 text-sm text-ink-soft">
                  Save one as{" "}
                  <code className="rounded bg-paper-deep px-1.5 py-0.5 font-mono text-xs">
                    public/screenshots/tabs/{tab.slug}.png
                  </code>
                </p>
              </div>
            </div>
          )}
        </figure>
      </article>
    </Reveal>
  );
}

export default function TabShowcase() {
  return (
    <section id="tabs" className="mx-auto max-w-6xl scroll-mt-24 px-5 py-24">
      <Reveal>
        <div className="max-w-2xl">
          <h2 className="font-display text-4xl font-semibold tracking-tight sm:text-5xl">
            Four tabs. Swipe sideways to move between them.
          </h2>
          <p className="mt-5 text-lg leading-relaxed text-ink-soft">
            Each one is a full tool, not a shortcut to somewhere else. Here is
            what every tab does.
          </p>
        </div>
      </Reveal>

      <div className="mt-20 space-y-24">
        {tabs.map((tab, index) => (
          <TabRow key={tab.slug} tab={tab} index={index} />
        ))}
      </div>
    </section>
  );
}
