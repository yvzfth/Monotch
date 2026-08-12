import Image from "next/image";
import Link from "next/link";
import { site } from "@/lib/site";

export default function Footer() {
  return (
    <footer className="mt-24 border-t-2 border-ink/10 bg-paper-deep">
      <div className="mx-auto grid max-w-6xl gap-10 px-5 py-14 sm:grid-cols-2 lg:grid-cols-4">
        <div className="sm:col-span-2">
          <div className="flex items-center gap-2.5">
            <Image
              src="/logo.png"
              alt=""
              width={36}
              height={36}
              className="sticker-sm rounded-xl bg-white"
            />
            <span className="font-display text-xl font-semibold">{site.name}</span>
          </div>
          <p className="mt-4 max-w-sm text-sm leading-relaxed text-ink-soft">
            {site.description}
          </p>
          <p className="mt-6 text-sm text-ink-soft">{site.requirements}</p>
        </div>

        <div>
          <h2 className="text-sm font-semibold">Product</h2>
          <ul className="mt-4 space-y-2.5 text-sm text-ink-soft">
            <li>
              <Link href="/#features" className="hover:text-ink">
                Features
              </Link>
            </li>
            <li>
              <Link href="/pricing" className="hover:text-ink">
                Pricing
              </Link>
            </li>
            <li>
              <Link href="/download" className="hover:text-ink">
                Download
              </Link>
            </li>
          </ul>
        </div>

        <div>
          <h2 className="text-sm font-semibold">Legal</h2>
          <ul className="mt-4 space-y-2.5 text-sm text-ink-soft">
            <li>
              <Link href="/legal/eula" className="hover:text-ink">
                Licence agreement
              </Link>
            </li>
            <li>
              <Link href="/legal/privacy" className="hover:text-ink">
                Privacy
              </Link>
            </li>
            <li>
              <a href={`mailto:${site.email}`} className="hover:text-ink">
                Support
              </a>
            </li>
          </ul>
        </div>
      </div>

      <div className="border-t-2 border-ink/10">
        <p className="mx-auto max-w-6xl px-5 py-6 text-xs text-ink-soft">
          © {new Date().getFullYear()} {site.author}. Made for the notch.
        </p>
      </div>
    </footer>
  );
}
