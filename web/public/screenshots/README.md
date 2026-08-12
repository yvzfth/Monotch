# Screenshots

Drop image files in this folder. The gallery on the homepage picks them up at
build time — there is no manifest to edit.

## Naming

The filename becomes the caption. A leading number controls order and is
stripped from the caption:

| File | Caption |
| --- | --- |
| `01-media-controls.png` | Media controls |
| `02-clipboard-tray.png` | Clipboard tray |
| `03-system-vitals.png` | System vitals |
| `04-camera-preview.png` | Camera preview |

`.png`, `.jpg`, `.jpeg`, `.webp` and `.avif` are all picked up. Anything else in
this folder (including this README) is ignored.

## Taking good ones

- `Shift-Cmd-4`, then `Space`, then click the notch panel captures just the
  island with its shadow. Hold `Option` while clicking to drop the shadow.
- The gallery crops to 16:10, so leave some desktop around the island rather
  than cropping tight to it.
- A calm wallpaper and a dark desktop make the island read clearly.
- Shoot on a Retina display and do not downscale — the gallery serves 2x.

Until at least one image is here, the homepage renders dashed placeholder tiles
naming the four shots worth taking.
