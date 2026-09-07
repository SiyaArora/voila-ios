# Voilà

An iOS app that rates your outfit and tells you how to elevate it — entirely on-device.

Snap or pick a photo, tap analyze, and get an honest 1–10 rating plus two to four
sentences on what's working and what to change. No account, no upload, no waiting on a
server.

<!-- Add screenshots here: docs/screenshot-picker.png, docs/screenshot-result.png -->

## The two rules

**1. Photos never leave the device.** There is no image upload, no image URL, and no
image data in any network request. Everything the app learns about your photo it learns
locally, using Apple's Vision framework and Apple Intelligence.

**2. The app works fully offline.** Analysis is on-device. The single network call in
the app is a best-effort prompt refresh that fails silently — it never blocks, delays,
or breaks a rating.

## How it works

Apple Intelligence's on-device language model is **text-only** — it cannot see the
image. So Voilà uses Vision to describe the photo in words first, then hands that text
to the model:

```
CGImage
  ├─ ClassifyImageRequest ──────────────────► labels    ("jacket", "denim")
  ├─ CalculateImageAestheticsScoresRequest ─► score     (-1 … 1)
  └─ ColorAnalyzer ─────────────────────────► colors    ("charcoal", "cream")
                                                  │
                                                  ▼
                                        text prompt (no pixels)
                                                  │
                                                  ▼
                              LanguageModelSession → @Generable OutfitRating
                                                       { rating: Int, feedback: String }
```

`ColorAnalyzer` is the interesting part. Vision's classifier returns generic labels with
no color information, so the analyzer fills the gap: it runs person segmentation to mask
out the background, downsamples to an 80×80 grid, maps each pixel to the nearest entry in
a curated reference palette, drops anything that lands on a skin tone, and keeps the
colors making up at least 8% of the remaining pixels. That's how the feedback can name
your actual palette instead of guessing.

## Project layout

```
voila/
  voilaApp.swift        @main entry point; warms the prompt config at launch
  ContentView.swift     the entire UI — picker, analyze button, result card
  OutfitAnalyzer.swift  Vision signals → Apple Intelligence → OutfitRating
  ColorAnalyzer.swift   person segmentation, pixel sampling, color naming
  PromptConfig.swift    optional remote stylist prompt, with offline fallback
```

## Requirements

- Xcode 26 or later
- iOS 26.5+ (`IPHONEOS_DEPLOYMENT_TARGET = 26.5`)
- **A physical device with Apple Intelligence enabled.** The Foundation Models framework
  is unavailable in the Simulator, so ratings only work on real hardware.

If Apple Intelligence is off, still downloading, or the device isn't eligible, the app
says so in a banner rather than failing silently.

## Build and run

```bash
git clone https://github.com/<you>/voila.git
cd voila
open voila.xcodeproj
```

Select your device, set your signing team, and run. No dependency step — there are no
third-party packages.

## Remote prompt config (optional)

`PromptConfig` fetches the stylist instruction text from a small config endpoint so the
prompt's tone can be tuned without shipping a new build:

```http
GET /config/prompt

{ "version": 3, "instructions": "You are Voilà, …", "updated_at": "2026-09-01T00:00:00Z" }
```

It sends no user data and no image — it is a plain GET. Three-second timeout, the last
good response cached in `UserDefaults`, a lower `version` never overwrites a higher one,
and any failure (offline, timeout, non-200, malformed) falls back to the instructions
compiled into `OutfitAnalyzer.instructions`. Point `promptEndpoint` at your own server or
delete the file; the app behaves the same either way.

## Conventions

- Swift concurrency (`async`/`await`). No completion handlers, no Combine.
- `struct` over `class` unless reference semantics are genuinely needed.
- Errors are typed enums conforming to `LocalizedError`.
- SwiftUI views break into private computed properties, not separate files, until a file
  passes ~300 lines.
- No third-party dependencies. Apple frameworks only.

## Contributing

PRs welcome. A few things are deliberately tuned and shouldn't be "improved" as a side
effect of unrelated work: `ColorAnalyzer`'s reference palette, skin-tone exclusion, and
0.08 share threshold; the Vision request pipeline in `extractSignals`; `ContentView`'s
layout and palette; and the Apple Intelligence availability cases in `unavailableMessage`.

Anything touching analysis or networking needs a real-device test, including airplane
mode.

## License

© 2026 VibesAI LLC. All rights reserved.

---

Made by [VibesAI LLC](https://github.com/), a small studio building privacy-first
on-device AI apps.
