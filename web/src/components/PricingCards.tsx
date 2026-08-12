import { checkout, plans } from "@/lib/site";

export default function PricingCards() {
  return (
    <div className="grid gap-6 lg:grid-cols-3">
      {plans.map((plan) => (
        <div
          key={plan.id}
          className={`sticker relative rounded-card bg-surface p-8 ${
            plan.featured ? "lg:-translate-y-3" : ""
          }`}
        >
          {plan.featured && (
            <span className="sticker-sm absolute -top-3.5 right-6 rounded-full bg-lemon px-3 py-1 text-xs font-bold text-on-accent">
              Best value
            </span>
          )}

          <span
            className={`sticker-sm inline-flex rounded-full ${plan.accent} px-3.5 py-1 text-xs font-bold text-on-accent`}
          >
            {plan.name}
          </span>

          <p className="mt-6 flex items-baseline gap-2">
            <span className="font-display text-5xl font-semibold tracking-tight">
              {plan.price}
            </span>
            <span className="text-sm text-ink-soft">{plan.cadence}</span>
          </p>

          <p className="mt-3 leading-relaxed text-ink-soft">{plan.blurb}</p>

          <ul className="mt-7 space-y-3">
            {plan.features.map((item) => (
              <li key={item} className="flex items-start gap-2.5 text-sm">
                <svg
                  aria-hidden
                  viewBox="0 0 20 20"
                  className="mt-0.5 h-4 w-4 shrink-0"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth={2.5}
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d="M4 10.5l4 4 8-9" />
                </svg>
                {item}
              </li>
            ))}
          </ul>

          <a
            href={checkout[plan.id]}
            className={`sticker sticker-press mt-8 block rounded-full px-6 py-3 text-center font-semibold ${
              plan.featured ? "bg-lemon text-on-accent" : "bg-paper-deep"
            }`}
          >
            Get {plan.name}
          </a>
        </div>
      ))}
    </div>
  );
}
