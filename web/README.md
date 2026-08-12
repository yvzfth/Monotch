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
| Copy, plans, prices, features, FAQ | `src/lib/site.ts` |
| Colours, fonts, sticker shadows | `src/app/globals.css` |
| Hero illustration | `src/components/NotchMock.tsx` |
| Screenshots | drop files in `public/screenshots/` |
| Pages | `src/app/**/page.tsx` |

## Logo and screenshots

The logo is the app icon, copied from
`Monotch/Assets.xcassets/AppIcon.appiconset`:

- `public/logo.png` — 1024px, used in the nav, footer, hero badge and social card
- `src/app/icon.png` + `src/app/apple-icon.png` — favicon and touch icon
- `src/app/opengraph-image.tsx` — social card, generated at build time from the
  same logo so the two can never drift apart

If you redraw the icon in Xcode, re-copy those three files.

Screenshots go in `public/screenshots/` and are listed at build time — see the
README in that folder for naming and capture tips. Until you add one, the
homepage gallery shows dashed placeholders instead of broken images.

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
