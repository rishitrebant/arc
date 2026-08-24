# ARC

### A native-feeling Live Activity system for macOS.

ARC turns the MacBook notch into a living surface for the things that are happening **right now**.

Not another notch utility.  
Not another floating widget.  
Not another dashboard.

The goal is simple:

> **Make the MacBook notch feel like a native part of macOS.**

---

## The idea

The macOS menu bar is great for things you need to access.

Notifications are great for things that need your attention.

But neither is ideal for something that is **currently happening**.

ARC is designed for that middle ground.

Music is playing.  
A call is coming in.  
An AirDrop is finishing.  
A device just connected.  
A download is progressing.

Instead of throwing another notification onto the screen, ARC gives ongoing activities a physical home:

**the notch.**

The island expands, morphs, communicates state, and quietly disappears when it is no longer relevant.

The experience should feel less like an application and more like an extension of the hardware itself.

---

## Design principles

ARC is built around a few uncompromising ideas.

### Native

Everything is built with native macOS technologies.

Swift.  
SwiftUI.  
AppKit.

No Electron.  
No React Native.  
No WebView.  
No HTML/CSS UI.

### Calm

The island should never compete with the application the user is working in.

No dashboards.  
No clutter.  
No unnecessary controls.

When there is nothing worth showing, ARC gets out of the way.

### Motion-first

Animation isn't decoration.

Motion explains:

- where an activity came from
- which activity owns the island
- when something changed
- when something completed
- what will happen next

Everything should **emerge from the notch and return to it**.

### Invisible

The ultimate goal is not:

> "Look at this cool notch app."

It is:

> "Wait, I thought this was part of macOS."

---

## What ARC can become

ARC is being designed as an activity system rather than a collection of unrelated features.

The product currently defines this priority hierarchy:

| Priority | Activity |
|---:|---|
| 1 | Incoming Call |
| 2 | Active Call |
| 3 | Music |
| 4 | Bluetooth |
| 5 | AirDrop |
| 6 | Downloads |
| 7 | Focus Mode |
| 8 | Timers |

Only **one activity owns the island at a time**.

When something more important happens, the current activity gracefully gives way.

When that activity finishes, the previous activity can return exactly where it left off.

This makes the island feel continuous rather than notification-driven.

---

## Current state

ARC is currently in **Sprint 1**.

The first implementation establishes the core architecture and the Music experience.

### Implemented

- Native Swift / SwiftUI / AppKit architecture
- Floating borderless island window
- Window anchored to the physical notch
- No Dock icon
- No normal application window
- No `⌘Tab` presence
- Non-activating panel
- Compact Music activity
- Expanded Music activity
- Hover-based expansion and collapse
- Animated waveform
- Album-art component
- Playback controls
- Playback progress UI
- Centralized design tokens
- Centralized animation tokens
- Activity abstraction
- Activity priority system
- Activity ownership management
- Type-erased activity storage
- Clean separation between feature logic and rendering

The current repository deliberately uses a `HardcodedMusicService` so the UI and architecture can be developed without coupling the first sprint to system-level now-playing APIs. 

### Current prototype

The Music activity currently renders a fixed playback state based on the design reference:

**Pepas — Farruko**

The playback state is intentionally mocked at this stage.

That means the project currently demonstrates the **experience and architecture**, not complete system-wide media detection.

---

## Architecture

ARC treats the architecture itself as part of the product.

Every activity is isolated.

Every responsibility has an owner.

The rough structure is:

```text
Island/
│
├── App/
│   ├── IslandApp.swift
│   └── AppDelegate.swift
│
├── Core/
│   ├── ActivityEngine/
│   │   ├── Activity.swift
│   │   ├── ActivityKind.swift
│   │   ├── ActivityManager.swift
│   │   └── AnyActivity.swift
│   │
│   ├── Configuration/
│   │   ├── DesignTokens.swift
│   │   └── AnimationTokens.swift
│   │
│   └── WindowManager/
│       ├── IslandWindow.swift
│       └── WindowManager.swift
│
├── Activities/
│   └── Music/
│       ├── MusicActivity.swift
│       ├── MusicModels.swift
│       ├── MusicService.swift
│       └── HardcodedMusicService.swift
│
└── UI/
    ├── Components/
    │   ├── AlbumArtView.swift
    │   ├── IslandShape.swift
    │   ├── PlaybackButton.swift
    │   ├── ProgressBar.swift
    │   └── Waveform.swift
    │
    ├── Compact/
    │   └── MusicCompactView.swift
    │
    ├── Expanded/
    │   └── MusicExpandedView.swift
    │
    └── IslandRootView.swift
```

### Activity architecture

Every activity follows the same conceptual model:

```text
Detection
   ↓
State
   ↓
Activity
   ↓
Compact / Expanded Rendering
   ↓
User Actions
```

Activities never directly communicate with one another.

Instead, they publish their state and the `ActivityManager` decides which activity owns the island.

This means adding something like Calls or Bluetooth should not require rewriting Music.

---

## Ownership and priority

One of ARC's most important architectural ideas is that activities do not compete for the UI.

The `ActivityManager` is the single authority responsible for deciding who owns the island.

For example:

```text
Music playing
      ↓
Music owns island
      ↓
Incoming call
      ↓
Call takes ownership
      ↓
Call ends
      ↓
Music returns
```

The previous activity does not need to restart from scratch.

This is intentional.

The island should feel like a continuous system rather than a series of disconnected notifications.

---

## Window system

The island is **not** implemented as a normal application window.

ARC uses an AppKit `NSPanel` configured as a borderless, non-activating system-style surface.

The window:

- stays attached to the notch
- remains horizontally centered
- does not steal focus
- has no title bar
- has no traffic lights
- cannot be moved
- cannot be resized
- can remain across Spaces
- stays above normal application content

The window manager owns only window concerns.

Feature logic never leaks into it.

---

## Animation system

Animation values live in `AnimationTokens.swift` rather than being scattered throughout individual views.

This keeps the motion language consistent across activities.

The current implementation separates:

- shape morphing
- content insertion/removal
- ownership transitions
- state changes
- hover activation
- hover deactivation
- transient activity duration

The most important rule is:

> **The island should never teleport from one state to another.**

It should morph.

Expand.  
Stretch.  
Compress.  
Slide.  
Return.

Never bounce for the sake of looking flashy.

---

## Design language

ARC follows a deliberately restrained visual system:

- Pure black surfaces
- Native macOS typography
- SF Symbols
- Minimal accent colors
- Strong whitespace
- Soft, continuous geometry
- Almost no decorative UI

Each activity can have its own accent while remaining visually part of the same system.

For example:

```text
Music       → Yellow
Bluetooth   → Blue
Calls       → Green
Downloads   → White
Focus       → Purple
```

The current Music implementation centralizes these values in `DesignTokens.swift`.

---

## Music

Music is the first activity being implemented because it represents the core ARC philosophy particularly well.

The current design supports:

- compact playback state
- hover expansion
- album artwork
- track title
- artist
- waveform
- elapsed time
- remaining time
- progress
- previous / play-pause / next controls

The architecture intentionally separates the Music UI from the underlying playback provider.

```text
MusicActivity
      │
      ▼
 MusicService
      │
      ├── HardcodedMusicService
      │
      └── Future system playback implementation
```

That means the rendering layer does not need to know where playback information comes from.

---

## Roadmap

ARC is being built incrementally around the activity system.

### Now

**Music**

- Compact state
- Expanded state
- Hover interaction
- Playback controls
- Progress UI
- Activity ownership architecture

### Next

**System integrations**

- Real now-playing detection
- Spotify integration
- Apple Music integration
- Incoming calls
- Active calls
- Bluetooth device states
- AirDrop
- Downloads
- Focus Mode

### Later

Potential activities include:

- Timers
- Screen recording
- Battery alerts
- Navigation
- Sports scores
- Flight tracking
- Food delivery

The goal is not to maximize the number of features.

A feature belongs in ARC only when it naturally behaves like a **Live Activity**.

---

## Requirements

ARC is currently intended for modern MacBooks with a physical notch.

Development requires:

- macOS 13+
- Xcode 15+
- Swift
- SwiftUI
- AppKit

The project is currently built as a native macOS application and intentionally avoids web-based UI technologies.

---

## Getting started

Clone the repository:

```bash
git clone https://github.com/rishitrebant/arc.git
cd arc
```

Open the Xcode project:

```bash
open Island.xcodeproj
```

Then run:

```text
⌘R
```

The current sprint uses a hardcoded music state, so no Spotify or Apple Music configuration is required to preview the Music experience.

---

## Project philosophy

ARC has two documents that act as its internal source of truth:

### Product philosophy

The product specification defines what ARC should feel like.

Its central principle is:

> The notch is not something to hide. It is something to extend.

### Engineering philosophy

The engineering constitution defines how ARC should be built.

The architecture prioritizes:

- readability
- maintainability
- scalability
- predictability
- reusable components
- isolated responsibilities
- native platform behavior

Product requirements take precedence over implementation convenience.

---

## The Apple test

Every significant decision comes back to one question:

> **Would Apple ship this?**

If the answer is uncertain, simplify.

Reduce.

Remove.

ARC is deliberately designed around restraint.

The objective is not to build the most feature-rich notch application.

The objective is to build the **most believable one**.

---

## Status

ARC is an early-stage experimental project and is actively being developed.

The current repository represents the first architectural/product sprint rather than a finished application.

Expect APIs, architecture, UI, and features to evolve as the project moves toward real system integrations.

---

## License

License information will be added as the project approaches a public release.

---

<p align="center">
  <strong>ARC</strong><br>
  <sub>The notch, extended.</sub>
</p>