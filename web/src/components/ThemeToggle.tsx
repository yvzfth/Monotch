"use client";

import { useEffect, useState } from "react";

type Theme = "light" | "dark" | "system";

const STORAGE_KEY = "monotch-theme";

function apply(theme: Theme) {
  const root = document.documentElement;
  if (theme === "system") {
    root.removeAttribute("data-theme");
  } else {
    root.setAttribute("data-theme", theme);
  }
}

/**
 * Three-state theme control: light, dark, or follow the OS.
 *
 * "System" removes the attribute entirely rather than resolving it to a value,
 * so the CSS media query stays in charge and the page keeps tracking the OS if
 * the visitor changes it while the tab is open.
 */
export default function ThemeToggle() {
  const [theme, setTheme] = useState<Theme>("system");
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    const stored = localStorage.getItem(STORAGE_KEY) as Theme | null;
    if (stored === "light" || stored === "dark") setTheme(stored);
    setMounted(true);
  }, []);

  function choose(next: Theme) {
    setTheme(next);
    apply(next);
    if (next === "system") {
      localStorage.removeItem(STORAGE_KEY);
    } else {
      localStorage.setItem(STORAGE_KEY, next);
    }
  }

  const isDark = theme === "dark";

  return (
    <button
      type="button"
      onClick={() => choose(isDark ? "light" : "dark")}
      // Lives inside the black island, so it is styled for that surface rather
      // than following the page theme.
      className="grid h-8 w-8 place-items-center rounded-full bg-white/10 text-white/80 transition-colors hover:bg-white/20 hover:text-white"
      aria-label={isDark ? "Switch to light theme" : "Switch to dark theme"}
      // Before hydration the button cannot know the stored choice, so the icon
      // is hidden rather than rendered wrong and swapped a frame later.
      style={{ visibility: mounted ? "visible" : "hidden" }}
    >
      <svg
        viewBox="0 0 24 24"
        className="h-4.5 w-4.5"
        fill="none"
        stroke="currentColor"
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden
      >
        {isDark ? (
          <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z" />
        ) : (
          <>
            <circle cx="12" cy="12" r="4" />
            <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
          </>
        )}
      </svg>
    </button>
  );
}
