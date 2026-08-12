import Link from "next/link";
import Hero from "@/components/Hero";
import Features from "@/components/Features";
import TabShowcase from "@/components/TabShowcase";
import PricingCards from "@/components/PricingCards";
import FAQ from "@/components/FAQ";
import Reveal from "@/components/Reveal";

export default function Home() {
  return (
    <>
      <Hero />
      <Features />
      <TabShowcase />

      <section className="border-y-2 border-ink/10 bg-paper-deep">
        <div className="mx-auto max-w-6xl px-5 py-24">
          <Reveal>
            <div className="max-w-2xl">
              <h2 className="font-display text-4xl font-semibold tracking-tight sm:text-5xl">
                Simple pricing. No account required to try it.
              </h2>
              <p className="mt-5 text-lg leading-relaxed text-ink-soft">
                Download it, use the free tier as long as you like, and upgrade
                when the clipboard tray has become muscle memory.
              </p>
            </div>
          </Reveal>

          <Reveal delay={80}>
            <div className="mt-14">
              <PricingCards />
            </div>
          </Reveal>
        </div>
      </section>

      <FAQ />

      <section className="mx-auto max-w-6xl px-5 pb-8">
        <Reveal>
        <div className="sticker rounded-card bg-lemon p-12 text-center text-on-accent">
          <h2 className="font-display text-4xl font-semibold tracking-tight">
            Give that black rectangle a job.
          </h2>
          <p className="mx-auto mt-4 max-w-md leading-relaxed text-on-accent/70">
            Free to download, quick to learn, and it disappears the moment you stop
            looking at it.
          </p>
          <Link
            href="/download"
            className="mt-8 inline-block rounded-full border-2 border-on-accent bg-white px-8 py-3.5 font-semibold text-on-accent shadow-[4px_4px_0_0_var(--color-on-accent)]"
          >
            Download for macOS
          </Link>
        </div>
        </Reveal>
      </section>
    </>
  );
}
