import type { Metadata } from "next";
import PricingCards from "@/components/PricingCards";
import FAQ from "@/components/FAQ";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Pricing",
  description: `Monthly, yearly and lifetime licences for ${site.name}.`,
};

const comparison: { feature: string; free: boolean; pro: boolean }[] = [
  { feature: "Collapsed island and tab switching", free: true, pro: true },
  { feature: "Media controls, artwork and lyrics", free: true, pro: true },
  { feature: "Clipboard history", free: false, pro: true },
  { feature: "File shelf and drag tray", free: false, pro: true },
  { feature: "System vitals and sensors", free: false, pro: true },
  { feature: "Fan control", free: false, pro: true },
  { feature: "Camera preview and capture", free: false, pro: true },
];

function Mark({ on }: { on: boolean }) {
  return on ? (
    <svg
      viewBox="0 0 20 20"
      className="mx-auto h-5 w-5"
      fill="none"
      stroke="currentColor"
      strokeWidth={2.5}
      strokeLinecap="round"
      strokeLinejoin="round"
      role="img"
      aria-label="Included"
    >
      <path d="M4 10.5l4 4 8-9" />
    </svg>
  ) : (
    <span className="text-ink-soft/40" role="img" aria-label="Not included">
      —
    </span>
  );
}

export default function PricingPage() {
  return (
    <>
      <section className="border-b-2 border-ink/10 bg-paper-deep">
        <div className="mx-auto max-w-6xl px-5 py-20">
          <h1 className="font-display text-5xl font-semibold tracking-tight">
            Pay once a year, or never again.
          </h1>
          <p className="mt-5 max-w-xl text-lg leading-relaxed text-ink-soft">
            Every plan unlocks the same features. Pick the billing that annoys you
            least — and refunds are open for 14 days either way.
          </p>

          <div className="mt-14">
            <PricingCards />
          </div>

          <p className="mt-8 text-sm text-ink-soft">
            Prices in USD. Tax is calculated at checkout by Lemon Squeezy, our
            merchant of record.
          </p>
        </div>
      </section>

      <section className="mx-auto max-w-3xl px-5 py-24">
        <h2 className="font-display text-3xl font-semibold tracking-tight">
          Free versus Pro
        </h2>

        <div className="sticker mt-8 overflow-hidden rounded-card bg-surface">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b-2 border-ink/10 bg-paper-deep">
                <th className="px-5 py-4 text-left font-semibold">Feature</th>
                <th className="w-24 px-3 py-4 font-semibold">Free</th>
                <th className="w-24 px-3 py-4 font-semibold">Pro</th>
              </tr>
            </thead>
            <tbody>
              {comparison.map((row) => (
                <tr key={row.feature} className="border-b border-ink/8 last:border-0">
                  <td className="px-5 py-4">{row.feature}</td>
                  <td className="px-3 py-4 text-center">
                    <Mark on={row.free} />
                  </td>
                  <td className="px-3 py-4 text-center">
                    <Mark on={row.pro} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <FAQ />
    </>
  );
}
