import { ImageResponse } from "next/og";
import { logoDataUri } from "./og-logo";
import { site } from "@/lib/site";

export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = `${site.name} — ${site.tagline}`;

/**
 * Social card, built from the real app icon.
 *
 * The icon arrives as a data URI from ./og-logo.ts rather than being read at
 * render time. Metadata routes are bundled without Node builtins, so `node:fs`
 * fails the build outright, and `fetch` of a file: URL is unimplemented.
 */
export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          alignItems: "flex-start",
          padding: "80px",
          backgroundColor: "#fffaf0",
        }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={logoDataUri}
          width={132}
          height={132}
          style={{
            borderRadius: 28,
            border: "4px solid #1c1917",
            backgroundColor: "#ffffff",
          }}
          alt=""
        />
        <div
          style={{
            marginTop: 44,
            fontSize: 76,
            fontWeight: 700,
            color: "#1c1917",
            letterSpacing: "-0.03em",
          }}
        >
          {site.name}
        </div>
        <div style={{ marginTop: 16, fontSize: 38, color: "#57534e" }}>
          {site.tagline}
        </div>
        <div
          style={{
            marginTop: 40,
            display: "flex",
            fontSize: 26,
            color: "#1c1917",
            backgroundColor: "#ffd23f",
            border: "4px solid #1c1917",
            borderRadius: 999,
            padding: "12px 30px",
            fontWeight: 600,
          }}
        >
          macOS · free to try
        </div>
      </div>
    ),
    size,
  );
}
