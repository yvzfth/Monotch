import Reveal from "./Reveal";
import { faqs } from "@/lib/site";

export default function FAQ() {
  return (
    <section id="faq" className="mx-auto max-w-3xl scroll-mt-24 px-5 py-24">
      <Reveal>
        <h2 className="font-display text-4xl font-semibold tracking-tight sm:text-5xl">
          Questions, answered.
        </h2>
      </Reveal>

      <div className="mt-12 space-y-4">
        {faqs.map((faq, index) => (
          <Reveal key={faq.q} delay={Math.min(index, 3) * 60}>
          <details
            className="sticker group rounded-card bg-surface p-6 open:bg-paper-deep"
          >
            <summary className="flex cursor-pointer list-none items-center gap-4 font-semibold select-none">
              {faq.q}
              <svg
                aria-hidden
                viewBox="0 0 20 20"
                className="ml-auto h-5 w-5 shrink-0 transition-transform group-open:rotate-45"
                fill="none"
                stroke="currentColor"
                strokeWidth={2.5}
                strokeLinecap="round"
              >
                <path d="M10 4v12M4 10h12" />
              </svg>
            </summary>
            <p className="mt-4 leading-relaxed text-ink-soft">{faq.a}</p>
          </details>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
