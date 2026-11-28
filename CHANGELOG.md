# Changelog

## 2.0.1

### Fixed
- **Updating works again.** 2.0 was published with a lower build number than 1.2.2, so ARC told people on 1.2.2 they were "up to date". Build numbers now only go up, and the release script refuses to publish one that doesn't.
- **Pills and cards fit any Mac's notch.** ARC measures the notch of the Mac it's on, so pills, cards and text sit clear of it on every model and display scaling instead of assuming a 179 × 32 pt notch.
- The launcher could stop opening from the notch hover or a card's back button after it had been opened once.
- Music and YouTube cards: the volume bar no longer swaps the open card for the volume pill; a browser notification chime no longer drops a playing video.
- Pomodoro's half of a shared pill is no longer cut off.
- Converting a Word document (.docx) from the shelf.

### New
- **Tools** in the launcher: camera mirror (with macOS background blur), Copy Text from anywhere on screen, colour picker, screenshot to clipboard, system activity, teleprompter, keyboard cleaning mode, Keep Awake.
- **Notes** with tabs, history and a pinned-to-notch note.
- **Up next** card as a song ends, with a skip button (Apple Music playlists).
- **Volume** on the Music card and in the launcher; a quiet volume pill when nothing else is on the island.
- Pomodoro **focus sounds** (rain, ocean, wind, fireplace, noise), a skip-break button, and a water reminder in the island.
- **File conversion** on the shelf: images, PDF, documents, audio and video.
- **Update and Restart** button in Settings → About when an update is waiting.
- Corner roundness and bounce settings; Settings reorganised with a Launcher tab.

## 1.1

### New
- **YouTube controls.** A video playing in your browser gets the same island as Music: thumbnail, title, channel, progress, and **back 5 s · play/pause · forward 5 s**, plus the output picker. The compact pill shows the YouTube logo or the video's thumbnail (your choice) and a waveform.
  - Optional — switch it off in Settings → Media.
  - "YouTube only" mode confirms the video is on YouTube by looking through the browser's tabs (macOS asks for Automation access to that browser); "Any video" controls whatever is playing.
  - Works with Safari, Chrome, Edge, Brave, Arc, Vivaldi, Opera and Firefox.
- **Expanded top corners.** Settings → Display lets you keep the expanded island rounded, or blend its top edge into the notch the way the compact pill does.
- **Redesigned Settings.** Native grouped forms, organised into General, Display, Media, Timers, Devices, Alerts and Shelf. The window is one fixed size (it used to grow past the screen), and it can now be minimised.
- **Pomodoro controls in Settings → Timers.**

### Fixed
- The AirPlay / output list now closes when you click the icon again (it used to close and immediately reopen).
- The YouTube compact pill is the same height as the other compact pills.

## 1.0

First release: Music, timers / stopwatch / pomodoro, Bluetooth audio, sound output, charging and low battery, calendar, downloads, privacy, Focus, Caps Lock, file shelf and AirDrop, the launcher with clipboard history, global shortcuts, Siri / Spotlight actions, haptics and accent-coloured glow.
