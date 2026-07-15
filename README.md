# Island — Sprint 1

A complete, buildable Xcode project. Unzip and open `Island.xcodeproj`,
then `⌘R`. No manual project setup, no dragging files in.

## Sprint 1 scope

- Native Swift, SwiftUI + AppKit
- Floating, borderless island window anchored under the notch
- No Dock icon, no Cmd+Tab presence (`LSUIElement`, `NSApp.setActivationPolicy(.accessory)`)
- Transparent, non-activating panel (`IslandWindow` / `WindowManager`)
- Hardcoded compact music UI matching `Ongoing music.png`
- Hover-to-expand also included (matches `Music Expanded.png`) since the
  generic hover-delay logic in `IslandRootView` was already built and costs
  nothing extra to include — happy to strip it back to compact-only if
  you'd rather keep this sprint's surface area smaller.

**Explicitly not in this sprint:** MediaRemote, Spotify integration,
Bluetooth, Calls, Downloads. `HardcodedMusicService` publishes one fixed
`MusicPlaybackState` ("Pepas" / Farruko, matching the Figma reference) so
the UI has real data to render without touching any private API yet.

## Project layout

```
Island.xcodeproj/         ← open this
Island/
  App/                     IslandApp.swift, AppDelegate.swift
  Core/
    Configuration/         DesignTokens.swift, AnimationTokens.swift
    ActivityEngine/         Activity.swift, ActivityKind.swift, ActivityManager.swift, AnyActivity.swift
    WindowManager/          IslandWindow.swift, WindowManager.swift
  Activities/Music/         MusicModels.swift, MusicService.swift, HardcodedMusicService.swift, MusicActivity.swift
  UI/
    Components/             Waveform.swift, AlbumArtView.swift, PlaybackButton.swift, ProgressBar.swift
    Compact/                MusicCompactView.swift
    Expanded/                MusicExpandedView.swift
    IslandRootView.swift
  Assets.xcassets/
```

## Requirements

- Xcode 15+
- macOS 13 (Ventura)+ deployment target — set in the project build settings
- **App Sandbox is off** by default in this project's build settings (no
  entitlements file included). Sprint 1 doesn't need it, but note for later:
  MediaRemote (a future sprint) requires the sandbox to stay off.

## Assumptions log (unchanged from prior delivery, still not resolved from source files)

| Value | Used | Status |
|---|---|---|
| Accent colors (hex) | Music = yellow, others reserved | **derived** — no hex given anywhere in the Figma exports or docs |
| Compact corner radius | `height / 2` (capsule) | **derived** — no annotation on the compact music measurement image |
| Expanded corner radius | `24pt` | **measured** — from the curve annotation on `Expanded Callpng.png` |
| Album art / compact icon radius | `16pt` / `6pt` | **measured** — from `Music Expanded.png` and `ongoing music.png` |
| All animation durations & curves | see `AnimationTokens.swift` | **derived** — PRODUCT.md only describes motion qualitatively |
| AirDrop/Downloads priority order | followed the numbered "Activity Priority System" list, not the earlier prose list (they disagree) | **flagged, not resolved** |

All of these live in `DesignTokens.swift` / `AnimationTokens.swift` so a
real value can drop in without touching any view code.

## Next sprint candidates

- Wire real MediaRemote detection behind `MusicService` (protocol already in place — see `Activities/Music/MusicService.swift`)
- Incoming/Active Call activity (has a Measurements export already)
- Resolve the AirDrop/Downloads priority-order discrepancy
