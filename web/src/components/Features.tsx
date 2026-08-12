import FeatureIcon from "./FeatureIcon";
import Reveal from "./Reveal";
import { features } from "@/lib/site";

export default function Features() {
  return (
    <section id="features" className="mx-auto max-w-6xl scroll-mt-24 px-5 py-24">
      <Reveal>
        <div className="max-w-2xl">
          <h2 className="font-display text-4xl font-semibold tracking-tight sm:text-5xl">
            One strip of black glass, five tools deep.
          </h2>
          <p className="mt-5 text-lg leading-relaxed text-ink-soft">
            Swipe sideways to move between tabs. Everything lives where your eyes
            already are, and collapses back to nothing when you are done.
          </p>
        </div>
      </Reveal>

      <div className="mt-14 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
        {features.map((feature, index) => (
          // Stagger by column so a row appears to sweep in rather than pop.
          <Reveal key={feature.title} delay={(index % 3) * 90} className="h-full">
            <article className="sticker h-full rounded-card bg-surface p-7">
              <span
                className={`sticker-sm grid h-12 w-12 place-items-center rounded-xl ${feature.accent} text-on-accent`}
              >
                <FeatureIcon name={feature.icon} />
              </span>
              <h3 className="mt-5 font-display text-xl font-semibold">
                {feature.title}
              </h3>
              <p className="mt-2.5 leading-relaxed text-ink-soft">
                {feature.body}
              </p>
            </article>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
