import Image from "next/image";
import Link from "next/link";
import ThemeToggle from "./ThemeToggle";
import { site } from "@/lib/site";

const links = [
  { href: "/#features", label: "Features" },
  { href: "/#tabs", label: "Tabs" },
  { href: "/pricing", label: "Pricing" },
  { href: "/#faq", label: "FAQ" },
];

export default function Nav() {
  return (
    <header className="sticky top-0 z-50 border-b-2 border-ink/10 bg-paper/85 backdrop-blur-md">
      <nav className="mx-auto flex max-w-6xl items-center gap-4 px-5 py-4">
        <Link href="/" className="flex items-center gap-2.5">
          <Image
            src="/logo.png"
            alt=""
            width={36}
            height={36}
            className="sticker-sm rounded-xl bg-white"
            priority
          />
          <span className="font-display text-xl font-semibold tracking-tight">
            {site.name}
          </span>
        </Link>

        <div className="ml-auto hidden items-center gap-7 sm:flex">
          {links.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="text-sm font-medium text-ink-soft transition-colors hover:text-ink"
            >
              {link.label}
            </Link>
          ))}
        </div>

        <div className="ml-auto flex items-center gap-2.5 sm:ml-0">
          <ThemeToggle />
          <Link
            href="/download"
            className="sticker sticker-press rounded-full bg-lemon px-5 py-2 text-sm font-semibold text-on-accent"
          >
            Download
          </Link>
        </div>
      </nav>
    </header>
  );
}
