export const site = {
  name: 'Monotch',
  tagline: 'Your notch, finally doing something.',
  description:
    'Monotch turns the MacBook notch into a control centre for media, clipboard, files, system vitals and your camera.',
  url: process.env.NEXT_PUBLIC_SITE_URL ?? 'https://monotch.vercel.app',
  email: 'fatihyavuz.js@gmail.com',
  author: 'Fatih Yavuz',
  requirements: 'macOS 14 Sonoma or later · Apple silicon and Intel',
};

/**
 * Reads an optional public env var.
 *
 * A var declared but left empty inlines as `""`, which is not nullish — so `??`
 * lets it through and every "Get" button ends up with `href=""`, which looks
 * live and does nothing when clicked. Empty and unset must mean the same thing.
 */
function configured(value: string | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

/**
 * Lemon Squeezy checkout URLs. Create the products in your store, then set these
 * in Vercel's environment variables. `null` until then, which the pricing cards
 * render as a disabled button rather than a link that goes nowhere.
 */
export const checkout = {
  monthly: configured(process.env.NEXT_PUBLIC_LS_CHECKOUT_MONTHLY),
  yearly: configured(process.env.NEXT_PUBLIC_LS_CHECKOUT_YEARLY),
  lifetime: configured(process.env.NEXT_PUBLIC_LS_CHECKOUT_LIFETIME),
};

export const downloadUrl = configured(process.env.NEXT_PUBLIC_DOWNLOAD_URL);

export type Plan = {
  id: keyof typeof checkout;
  name: string;
  price: string;
  cadence: string;
  blurb: string;
  features: string[];
  accent: string;
  featured?: boolean;
};

export const plans: Plan[] = [
  {
    id: 'monthly',
    name: 'Monthly',
    price: '$3',
    cadence: 'per month',
    blurb: 'Try the whole thing. Cancel whenever you like.',
    features: [
      'Every Pro feature',
      'Updates while subscribed',
      '2 Macs per licence',
      'Cancel in one click',
    ],
    accent: 'bg-sky',
  },
  {
    id: 'yearly',
    name: 'Yearly',
    price: '$24',
    cadence: 'per year',
    blurb: 'Two thirds the price of monthly, billed once.',
    features: [
      'Every Pro feature',
      'Updates while subscribed',
      '3 Macs per licence',
      'Priority email support',
    ],
    accent: 'bg-lemon',
    featured: true,
  },
  {
    id: 'lifetime',
    name: 'Lifetime',
    price: '$59',
    cadence: 'one time',
    blurb: 'Pay once. Keep it, and every update in this major version.',
    features: [
      'Every Pro feature',
      'All 1.x updates included',
      '3 Macs per licence',
      'No renewals, ever',
    ],
    accent: 'bg-lime',
  },
];

export const features = [
  {
    title: 'Media that stays out of the way',
    body: 'Artwork, scrubbing, volume and synced lyrics for Music, Spotify and anything playing in a browser tab.',
    accent: 'bg-grape',
    icon: 'music',
  },
  {
    title: 'A clipboard with a memory',
    body: 'Recent text, images and files kept in a tray you can scroll, pin and paste from without breaking flow.',
    accent: 'bg-sky',
    icon: 'clipboard',
  },
  {
    title: 'Drag files to the shelf',
    body: 'Drop anything into the notch and carry it between apps, Spaces and full-screen windows.',
    accent: 'bg-coral',
    icon: 'files',
  },
  {
    title: 'Vitals at a glance',
    body: 'CPU, memory, storage, fan speeds and temperature sensors. Hide the cards your Mac has no hardware for.',
    accent: 'bg-lime',
    icon: 'gauge',
  },
  {
    title: 'Camera in the notch',
    body: 'A live preview with Portrait and Studio Light, plus a capture tray for stills and clips you can drag straight out.',
    accent: 'bg-lemon',
    icon: 'camera',
  },
  {
    title: 'Follows you everywhere',
    body: 'Sits above full-screen apps and every Space, and never steals focus from what you were doing.',
    accent: 'bg-paper-deep',
    icon: 'layers',
  },
];

export type Tab = {
  slug: string;
  name: string;
  icon: string;
  accent: string;
  headline: string;
  body: string;
  points: string[];
};

/** The four tabs of the island, in the order they sit in the app. */
export const tabs: Tab[] = [
  {
    slug: 'media',
    name: 'Media',
    icon: 'music',
    accent: 'bg-grape',
    headline: 'Whatever is playing, wherever it is playing.',
    body: 'Apple Music, Spotify and audio in any browser tab land in the same place. Artwork on the left, controls under your cursor, and the whole thing folds away when the song does not need you.',
    points: [
      'Scrub the timeline and set volume without opening the app',
      'Time-synced lyrics pulled from LRCLIB, scrolling with the track',
      'Queue and source list one swipe down',
      'Switch between players when two things are fighting over playback',
    ],
  },
  {
    slug: 'clipboard',
    name: 'Clipboard',
    icon: 'clipboard',
    accent: 'bg-sky',
    headline: 'The last thing you copied is never gone.',
    body: 'Text, images and files are kept in a scrollable history, next to a shelf you can drop files onto and carry between apps and Spaces.',
    points: [
      'Copy back any recent snippet, image or file with one click',
      'Drag files onto the shelf and out again into any window',
      'A folder tray watching Downloads, or any folder you point it at',
      'Clear an item, or the whole history, from the notch',
    ],
  },
  {
    slug: 'system',
    name: 'System',
    icon: 'gauge',
    accent: 'bg-lime',
    headline: 'Vitals without a menu bar full of numbers.',
    body: 'CPU, memory, storage, fans and temperature sensors in one panel. Hover any card to expand it into detail; hide the ones you never look at.',
    points: [
      'CPU load, memory pressure and disk usage at a glance',
      'Fan speeds with Auto, Silent, Balanced, Performance and Max modes',
      'Temperature sensors, showing only the ones your Mac actually reports',
      'Remove any card you do not want and keep the notch short',
    ],
  },
  {
    slug: 'camera',
    name: 'Camera',
    icon: 'camera',
    accent: 'bg-lemon',
    headline: 'A mirror, and a camera roll, in the notch.',
    body: 'Check your framing before a call without opening anything, then take a still or a clip and drag it straight into the conversation.',
    points: [
      'Live preview that expands from a circle to a wide view',
      'Portrait, Studio Light and Reactions from the effects button',
      'Hold the shutter to record, tap it for a photo',
      'Captures stack in a tray you can drag into any app',
    ],
  },
];

export const faqs = [
  {
    q: 'Which Macs does it work on?',
    a: 'Any Mac running macOS 14 or later. A physical notch makes it feel at home, but Monotch also runs as a floating island on Macs and external displays without one.',
  },
  {
    q: 'What do I get for free?',
    a: 'Media controls and the collapsed island are free forever. Clipboard history, the file shelf, system monitoring, fan control and the camera are Pro.',
  },
  {
    q: 'How many Macs can I use one licence on?',
    a: 'Two on Monthly, three on Yearly and Lifetime. You can release a Mac from your licence at any time in Settings, so replacing a machine is not a support ticket.',
  },
  {
    q: 'What happens if my subscription ends?',
    a: 'Monotch keeps running and drops back to the free features. Nothing is deleted, and your clipboard history and captures stay on your Mac.',
  },
  {
    q: 'Does it work offline?',
    a: 'Yes. The licence is checked in the background every few weeks and keeps working for two weeks without a connection, so a flight or a dead router never locks you out.',
  },
  {
    q: 'Can I get a refund?',
    a: `Within 14 days, no questions asked. Email ${site.email} and it is done.`,
  },
];
