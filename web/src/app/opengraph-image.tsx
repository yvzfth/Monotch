import { readFile } from "node:fs/promises";
import path from "node:path";
import { ImageResponse } from "next/og";
import { site } from "@/lib/site";

export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = `${site.name} — ${site.tagline}`;

// Generated at build time from the real app icon, so the social card and the
// app can never drift apart.
export default async function OpengraphImage() {
  const logo = await readFile(path.join(process.cwd(), "public", "logo.png"));
  const logoSrc = `data:image/png;base64,${logo.toString("base64")}`;

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
        <img
          src={logoSrc}
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
