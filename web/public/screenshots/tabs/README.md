# Tab screenshots

One image per tab, named after the tab. The showcase section on the homepage
picks them up at build time — there is no manifest to edit.

| File | Section |
| --- | --- |
| `media.png` | Media tab |
| `clipboard.png` | Clipboard tab |
| `system.png` | System tab |
| `camera.png` | Camera tab |

`.png`, `.jpg`, `.jpeg`, `.webp` and `.avif` all work. Any tab without a file
renders a dashed placeholder naming the path it expects, so a missing shot never
shows as a broken image.

## Taking good ones

- `Shift-Cmd-4`, then `Space`, then click the notch panel captures just the
  island with its shadow. Hold `Option` while clicking to drop the shadow.
- The frame crops to 16:10, so leave some desktop around the island rather than
  cropping tight to it.
- Open the tab you are shooting and let it settle — the camera tab in particular
  needs a moment for the preview to warm up.
- Shoot on a Retina display and do not downscale; the layout serves 2x.
