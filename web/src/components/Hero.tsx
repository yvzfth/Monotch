import Image from "next/image";
import Link from "next/link";
import NotchMock from "./NotchMock";
import { site } from "@/lib/site";

export default function Hero() {
  return (
    <section className="relative overflow-hidden border-b-2 border-ink/10">
      <div
        aria-hidden
        className="pointer-events-none absolute -top-32 left-1/2 h-96 w-184 -translate-x-1/2 rounded-full bg-lemon/35 blur-3xl"
      />

      <div className="relative mx-auto grid max-w-6xl items-center gap-14 px-5 py-20 lg:grid-cols-2 lg:py-28">
        <div>
          <p className="sticker-sm inline-flex items-center gap-2 rounded-full bg-surface py-1.5 pr-4 pl-1.5 text-xs font-semibold">
            <Image
              src="/logo.png"
              alt=""
              width={22}
              height={22}
              className="rounded-full"
            />
            For MacBook Pro &amp; Air
          </p>

          <h1 className="mt-6 font-display text-5xl leading-[1.05] font-semibold tracking-tight sm:text-6xl">
            Your notch,
            <br />
            <span className="relative inline-block">
              <span
                aria-hidden
                className="absolute inset-x-0 bottom-1.5 h-4 -rotate-1 bg-lemon"
              />
              <span className="relative">finally useful.</span>
            </span>
          </h1>

          <p className="mt-6 max-w-md text-lg leading-relaxed text-ink-soft">
            {site.description}
          </p>

          <div className="mt-9 flex flex-wrap items-center gap-3">
            <Link
              href="/download"
              className="sticker sticker-press rounded-full bg-lemon px-7 py-3.5 font-semibold text-on-accent"
            >
              Download for macOS
            </Link>
            <Link
              href="/pricing"
              className="sticker sticker-press rounded-full bg-surface px-7 py-3.5 font-semibold"
            >
              See pricing
            </Link>
          </div>

          <p className="mt-5 text-sm text-ink-soft">
            Free forever for media controls · {site.requirements}
          </p>
        </div>

        <NotchMock />
      </div>
    </section>
  );
}
