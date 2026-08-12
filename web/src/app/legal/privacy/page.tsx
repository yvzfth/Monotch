import type { Metadata } from "next";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Privacy",
  description: `How ${site.name} handles your data.`,
};

const sections = [
  {
    title: "What stays on your Mac",
    body: "Clipboard history, camera captures, file shelf contents, media metadata and every system reading are stored locally and never uploaded. Monotch has no analytics and no crash reporting service.",
  },
  {
    title: "What licensing sends",
    body: "When you activate a licence, the app sends your licence key, a salted hash of your Mac's hardware identifier, and the app version. The hash cannot be reversed into a serial number, and it exists only to enforce the per-licence device limit.",
  },
  {
    title: "What payments involve",
    body: "Purchases are handled by Lemon Squeezy as merchant of record. They receive your billing details and email address under their own privacy policy; the developer never sees your card details.",
  },
  {
    title: "Third-party services",
    body: "Lyrics are fetched from LRCLIB using the current track's title and artist. No identifier of you or your Mac is attached to those requests.",
  },
  {
    title: "Your rights",
    body: "You can ask for a copy of the activation records tied to your licence, or have them deleted, by emailing the address below. Deleting them releases every device on the licence.",
  },
];

export default function PrivacyPage() {
  return (
    <section className="mx-auto max-w-3xl px-5 py-20">
      <h1 className="font-display text-4xl font-semibold tracking-tight">
        Privacy
      </h1>
      <p className="mt-5 text-lg leading-relaxed text-ink-soft">
        Monotch reads a lot about your Mac and sends almost none of it anywhere.
      </p>

      <div className="mt-12 space-y-4">
        {sections.map((section) => (
          <article key={section.title} className="sticker rounded-card bg-surface p-7">
            <h2 className="font-display text-xl font-semibold">{section.title}</h2>
            <p className="mt-2.5 leading-relaxed text-ink-soft">{section.body}</p>
          </article>
        ))}
      </div>

      <p className="mt-10 text-sm text-ink-soft">
        Questions or requests:{" "}
        <a href={`mailto:${site.email}`} className="font-semibold text-ink underline">
          {site.email}
        </a>
        . This page describes the intended licensing design — review it against
        what you actually ship before launch.
      </p>
    </section>
  );
}
