# Voilà

An iOS app that rates an outfit photo and gives styling feedback. All analysis runs
on-device using Apple's Vision framework and Apple Intelligence (Foundation Models).

## The two rules

**1. Photos never leave the device.** There is no image upload, no image URL, no
image data in any network request, ever. This is the product, not a preference. If a
task seems to require sending a photo somewhere, stop and say so instead of building it.

**2. The app must work fully offline.** Analysis is on-device and must stay that way.
Any network call is an enhancement that fails silently — never a blocker. No spinner
waiting on the network, no error banner when a fetch fails, no code path where a
timeout delays a rating.

## Layout

```
voila/
  voilaApp.swift        @main entry point
  ContentView.swift     the entire UI — picker, analyze button, result card
  OutfitAnalyzer.swift  Vision signals -> Apple Intelligence -> OutfitRating
  ColorAnalyzer.swift   person segmentation, pixel sampling, color naming
```

## How analysis works

`ContentView` loads a `CGImage` from `PhotosPicker`, then calls `OutfitAnalyzer.analyze`:

1. `ClassifyImageRequest` returns labels ("jacket", "denim")
2. `CalculateImageAestheticsScoresRequest` returns a score from -1 to 1
3. `ColorAnalyzer` masks out background and skin, tallies pixels, names the colors
4. Those three signals are formatted into a text prompt
5. `LanguageModelSession` returns a `@Generable` `OutfitRating` (rating 1-10 + feedback)

Step 4 exists because Apple Intelligence's on-device model is text-only — it cannot see
the image. The Vision signals are how the model learns anything about the photo.

## Don't touch without being asked

- `ColorAnalyzer` — the reference palette, skin-tone exclusion, and the 0.08 share
  threshold are tuned. Don't "improve" the color math.
- The Vision request pipeline in `extractSignals`.
- `ContentView`'s layout and the `Self.background` / `ink` / `muted` palette.
- `unavailableMessage` — the Apple Intelligence availability cases are deliberate.

Refactoring these while doing unrelated work is the main failure mode here.

## Conventions

- Swift concurrency (`async`/`await`). No completion handlers, no Combine.
- `struct` over `class` unless reference semantics are actually needed.
- Errors are typed enums conforming to `LocalizedError`, like `AnalyzerError`.
- SwiftUI views break into private computed properties (`header`, `resultCard`), not
  separate files, until a file exceeds ~300 lines.
- No third-party dependencies. No SPM packages, no CocoaPods. Apple frameworks only.

## Networking

There is currently no networking in this app. When it is added:

- `URLSession` directly. No networking library.
- 3 second timeout, maximum.
- Every fetch has a local fallback and fails silently to it.
- HTTPS only (App Transport Security rejects plain HTTP).
- Cache the last good response in `UserDefaults` so a cold launch offline still works.

## Verification

Xcode builds are not automatic here — `xcodebuild` may not be available in this
environment. If you cannot build, say so plainly rather than claiming the code compiles.

For any change, state explicitly:

- what you changed and why
- what you verified, and how
- what you could NOT verify

Anything touching analysis or networking needs a real device test by the user, including
airplane mode. Do not describe such work as done — hand it back with the test steps.

## Context

Voilà is made by VibesAI LLC, a small studio building privacy-first on-device AI apps.
The related backend lives in a separate repo and serves configuration only — never
user data, never images.
