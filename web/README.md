# Monotch — marketing site

Next.js 15 (App Router) + Tailwind v4. Static, no database, no client JS beyond
what Next ships.

## Run it

```bash
cd web
npm install
npm run dev
```

## Deploy to Vercel

The site lives in a subfolder of the Swift repo, so tell Vercel where it is:

1. Import the repo at [vercel.com/new](https://vercel.com/new).
2. Set **Root Directory** to `web`.
3. Framework preset is detected as Next.js — leave build and output settings alone.
4. Add the environment variables below, then deploy.

Alternatively from the CLI:

```bash
cd web
npx vercel --prod
```

## Environment variables

Copy `.env.example` to `.env.local` for development, and add the same keys in
Vercel → Settings → Environment Variables.

| Variable | What it does |
| --- | --- |
| `NEXT_PUBLIC_SITE_URL` | Canonical URL for metadata and Open Graph tags |
| `NEXT_PUBLIC_LS_CHECKOUT_MONTHLY` | Lemon Squeezy checkout link for the monthly plan |
| `NEXT_PUBLIC_LS_CHECKOUT_YEARLY` | Checkout link for the yearly plan |
| `NEXT_PUBLIC_LS_CHECKOUT_LIFETIME` | Checkout link for the lifetime plan |
| `NEXT_PUBLIC_DOWNLOAD_URL` | Direct link to the notarised `.dmg` |

Unset checkout links fall back to `/pricing`, and an unset download URL renders a
placeholder instead of a dead button — the site is safe to deploy before the
store and the build exist.

## Where to edit things

| What | Where |
| --- | --- |
| Copy, plans, prices, features, FAQ, tab write-ups | `src/lib/site.ts` |
| Colours, fonts, dark theme, sticker shadows | `src/app/globals.css` |
| Hero illustration | `src/components/NotchMock.tsx` |
| The notch-shaped navigation | `src/components/Nav.tsx` |
| Screenshots | drop files in `public/screenshots/tabs/` |
| Pages | `src/app/**/page.tsx` |

## The navigation

The nav is a black island fixed to the top of the page that expands on hover —
a live demo of what the app does under a real notch. Expansion is pure CSS
(`group-hover` plus `group-focus-within`), so it opens for keyboard users too
and stays a server component. Hover does not exist on touch, so below the `sm`
breakpoint the island renders permanently open with the text links dropped.

## Dark theme

Three states: light, dark, or follow the OS. Only the neutral tokens in
`globals.css` flip — accents stay put, and because the sticker borders and
shadows are drawn with `--color-ink`, the whole treatment inverts for free.

Two rules worth keeping in mind when adding components:

- Use `bg-surface`, never `bg-white`, for anything that should follow the theme.
- Put `text-on-accent` on text sitting over an accent fill. `--color-ink` turns
  cream in dark mode, which is unreadable on lemon.

## Logo and screenshots

The logo is the app icon, copied from
`Monotch/Assets.xcassets/AppIcon.appiconset`:

- `public/logo.png` — 1024px, used in the nav, footer, hero badge and social card
- `src/app/icon.png` + `src/app/apple-icon.png` — favicon and touch icon
- `src/app/opengraph-image.tsx` — social card, generated at build time from the
  same logo so the two can never drift apart

If you redraw the icon in Xcode, re-copy those three files and regenerate the
social card's copy of it. Metadata routes are bundled without Node builtins, so
the card cannot read the PNG at render time — `node:fs` fails the build and
`fetch` of a `file:` URL is unimplemented. The icon is inlined as a data URI
instead:

```bash
# from the repo root
node -e '
const fs=require("fs");
const b64=fs.readFileSync("Monotch/Assets.xcassets/AppIcon.appiconset/icon_256x256.png").toString("base64");
fs.writeFileSync("web/src/app/og-logo.ts",`export const logoDataUri =\n  "data:image/png;base64,${b64}";\n`);
'
```

Screenshots go in `public/screenshots/tabs/`, one per tab, named `media.png`,
`clipboard.png`, `system.png` and `camera.png`. They are resolved at build time —
see the README in that folder for capture tips. Any tab without a file renders a
dashed placeholder instead of a broken image.

Prices in `src/lib/site.ts` are placeholders. They are display-only — the real
amount charged is whatever the Lemon Squeezy product says, so change both.

## Fonts

Lemon Squeezy's own typefaces are commercially licensed and cannot be
redistributed, so this uses the closest freely licensed pairing: **Fraunces**
for display and **Inter** for UI, both self-hosted at build time by `next/font`.
If you license the real faces, swap them in `src/app/layout.tsx` and the
`--font-display` / `--font-sans` tokens in `globals.css`.

The visual language — warm paper background, hard offset "sticker" shadows,
chunky rounded cards, lemon accent — is an homage, not a copy. Do not use Lemon
Squeezy's logo or wordmark anywhere on the site.

## Before you take money

- The EULA page renders the repo's `LICENSE`, which is still written for App
  Store distribution. Rewrite it for direct sale.
- `src/app/legal/privacy/page.tsx` describes the *intended* licensing design.
  Make it match what you actually ship.
