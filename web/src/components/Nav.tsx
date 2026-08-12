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

/**
 * The navigation is the product: a black island hanging from the top of the
 * screen that expands when you approach it, exactly like Monotch does under a
 * real notch.
 *
 * Expansion is pure CSS — `group-hover` plus `group-focus-within`, so it opens
 * for a keyboard as readily as for a pointer and the whole thing stays a server
 * component. Hover does not exist on touch, so below `sm` the island is simply
 * rendered open.
 */
export default function Nav() {
  return (
    <header className="pointer-events-none fixed inset-x-0 top-0 z-50 flex justify-center">
      <div className="group pointer-events-auto">
        <div
          className={[
            "relative flex items-center justify-center overflow-hidden bg-[#0b0b0c]",
            "rounded-b-card shadow-[0_10px_30px_-6px_rgba(0,0,0,0.55)]",
            "transition-[width,height] duration-420 ease-[cubic-bezier(0.22,1,0.36,1)]",
            // Collapsed on pointer devices, opening on hover or keyboard focus.
            "h-9 w-60 sm:group-hover:h-16 sm:group-hover:w-176",
            "sm:group-focus-within:h-16 sm:group-focus-within:w-176",
            // Touch devices get the open state permanently.
            "max-sm:h-16 max-sm:w-[min(94vw,26rem)]",
          ].join(" ")}
        >
          {/* Resting state: just the mark and the wordmark, like the collapsed nub.
              Decorative, and `pointer-events-none` because a faded-out element
              still swallows clicks — without it this layer sits over the links
              once the island opens and shows a text cursor instead. */}
          <div
            aria-hidden
            className="pointer-events-none absolute flex items-center gap-2 transition-opacity duration-200 group-hover:opacity-0 group-focus-within:opacity-0 max-sm:hidden"
          >
            <Image
              src="/logo.png"
              alt=""
              width={18}
              height={18}
              className="rounded-[5px] bg-white"
              priority
            />
            <span className="text-[13px] font-semibold tracking-wide text-white/80">
              {site.name}
            </span>
          </div>

          {/* Expanded state. Kept in the DOM at all times so links stay focusable,
              which is also what triggers the open state for keyboard users. */}
          <div
            className={[
              "flex w-full items-center gap-3 px-5 opacity-0 transition-opacity duration-200",
              "sm:group-hover:opacity-100 sm:group-focus-within:opacity-100",
              // Invisible while collapsed, so it must not take clicks either —
              // otherwise the nub hides live links behind it.
              "pointer-events-none sm:group-hover:pointer-events-auto sm:group-focus-within:pointer-events-auto",
              "max-sm:pointer-events-auto max-sm:opacity-100",
            ].join(" ")}
          >
            <Link href="/" className="flex shrink-0 items-center gap-2">
              <Image
                src="/logo.png"
                alt={site.name}
                width={26}
                height={26}
                className="rounded-lg bg-white"
              />
              <span className="font-display text-base font-semibold text-white max-sm:hidden">
                {site.name}
              </span>
            </Link>

            <div className="ml-4 flex items-center gap-6 max-sm:hidden">
              {links.map((link) => (
                <Link
                  key={link.href}
                  href={link.href}
                  className="text-sm font-medium text-white/60 transition-colors hover:text-white focus-visible:text-white"
                >
                  {link.label}
                </Link>
              ))}
            </div>

            <div className="ml-auto flex shrink-0 items-center gap-2.5">
              <ThemeToggle />
              <Link
                href="/download"
                className="rounded-full bg-lemon px-4 py-1.5 text-sm font-semibold text-on-accent transition-transform hover:scale-105"
              >
                Download
              </Link>
            </div>
          </div>
        </div>
      </div>
    </header>
  );
}
