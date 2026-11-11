# RMQ brand assets

RMQ is a focused openEuler RabbitMQ distribution, not a general API gateway.
The mark represents three queued messages, a routing path, and a protected
payload node inside a stable hexagonal boundary. It deliberately does not use
the RabbitMQ rabbit mark or imply RabbitMQ upstream ownership.

The supplied lockup uses:

- primary wordmark and mark: `rmq-logo.svg` on light backgrounds;
- dark-background lockup: `rmq-logo-dark.svg`;
- square mark: `rmq-mark.svg` / `rmq-mark-dark.svg`;
- GitHub avatar and favicon: `rmq-mark-512.png`, `rmq-mark-128.png`,
  `rmq-mark-32.png`, or `rmq-favicon.svg`.

## Palette

| Role | Light background | Dark background |
|---|---|---|
| Navy / structure | `#101F32` | `#F4F7FB` |
| Message teal | `#0E93A3` | `#28B8C4` |
| Protected payload amber | `#D98A2B` | `#F2B45C` |
| Secondary text | `#506A7E` | `#9FC2D2` |

The lighter teal and amber values keep the small strokes legible on white while
retaining the `#28B8C4` / `#F2B45C` brand accents for dark presentations.

## Typography and lockup

Use Inter or Manrope when available, falling back to Helvetica Neue or Arial.
Keep the wordmark and subtitle on the same baseline as the provided SVG. Do not
stretch, rotate, add a drop shadow, or place the light lockup on a dark field.

The tagline used in the lockup is `RELIABLE MESSAGE QUEUE`; the longer campaign
line is **Reliable Messaging. Protected Payloads.**

## PNG files

All PNG files have transparent backgrounds:

- `rmq-logo.png` and `rmq-logo-dark.png`: 440 × 170 horizontal lockups;
- `rmq-mark-512.png`, `rmq-mark-256.png`, `rmq-mark-128.png`,
  `rmq-mark-64.png`, `rmq-mark-40.png`, `rmq-mark-32.png`,
  `rmq-mark-16.png`: square marks;
- `rmq-mark-dark-512.png`: square mark for dark backgrounds;
- `rmq-favicon.png`: 128 × 128 dark rounded-square icon.

For GitHub repository avatars, use `rmq-mark-512.png` or `rmq-mark-128.png`.
The 32 px and 16 px marks are provided for browser and desktop icon fallbacks.
