# VoiceShot Pro 🎙️📸

> **Voice-activated screenshot utility for macOS.** Numbers your open windows and captures displays, apps, or cropped regions instantly with voice commands like **`"snap1"`**, **`"snap2"`**, or **`"screenshot 1"`**, automatically copying captures to your clipboard.

![macOS 12+](https://img.shields.io/badge/macOS-12.0%2B-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-purple)
![Zero Dependencies](https://img.shields.io/badge/Dependencies-Zero%20External%20Pkgs-brightgreen)
![Status](https://img.shields.io/badge/Status-Tested%20%26%20Verified-success)

---

## 📖 Table of Contents

- [Overview](#-overview)
- [Key Features](#-key-features)
- [Window Numbering System (`snap1`, `snap2`, `snap3`...)](#-window-numbering-system-snap1-snap2-snap3)
- [Voice Commands Reference](#-voice-commands-reference)
- [Quick Start & Installation](#-quick-start--installation)
- [First-Time Permissions](#-first-time-permissions)
- [Menu Bar & Keyboard Shortcuts](#-menu-bar--keyboard-shortcuts)
- [Preferences & Customization](#-preferences--customization)
- [Architecture & Source Tour](#-architecture--source-tour)
- [Development & Automated Testing](#-development--automated-testing)
- [Troubleshooting](#-troubleshooting)

---

## 🎯 Overview

**VoiceShot Pro** is an ultra-lightweight (~20MB RAM) native macOS menu bar app designed for power users, developers, presenters, and multitaskers. Instead of memorizing multi-key shortcuts or searching for windows, simply speak naturally:

```
"snap1" ➔ Captures Window 1 & copies to clipboard
"snap2" ➔ Captures Window 2 & copies to clipboard
"show numbers" ➔ Flashes floating number badges on all open windows
"screenshot Safari" ➔ Captures Safari's front window
"screenshot area" ➔ Launches interactive selection crosshairs
"screenshot text" ➔ Transcribes on-screen text with Vision OCR
```

By default, screenshots go directly to the macOS **pasteboard**, ready to paste (`Cmd + V`) straight into Slack, Discord, Messages, Figma, Google Docs, or Jira.

---

## ✨ Key Features

- 🔢 **Dynamic Window Numbering**: Indexes visible windows from front to back `[ 1 ]`, `[ 2 ]`, `[ 3 ]`, `[ 4 ]`, `[ 5 ]...`.
- 🏷️ **On-Screen Badge Overlays**: Say `"show numbers"` or press `Cmd + Shift + N` to flash floating badge overlays on the top-left of each window.
- ⚡ **Rapid Shorthand Voice Triggers**: Say “snap one,” “snap two,” or any window number through ten. The Live Monitor lists these commands as `snap1` through `snap10`.
- 📋 **Zero-Click Clipboard Copying**: The image goes directly to the clipboard. Turn on **Save Screenshots Locally** in the menu or Preferences to also keep a PNG.
- 🖼️ **CleanShot-Style Floating Preview**: The thumbnail lets you copy the image again. Saved captures also offer Preview, Finder, and Trash:
  - `📋 Copy`: Re-copy to clipboard
  - `✏️ Preview`: Open directly in macOS Preview app
  - `📂 Finder`: Reveal file in Finder
  - `🗑️ Trash`: Instantly delete accidental captures
- 📝 **On-Device Vision OCR**: Transcribe text visible on screen into editable clipboard text with `"screenshot text"` or `"copy text"`.
- 🪟 **App Name Targeting**: Capture specific applications by name: `"screenshot Safari"`, `"screenshot Terminal"`, `"screenshot Slack"`, `"screenshot Code"`.
- ⏱️ **Voice Countdown Timer**: Say `"screenshot in 3 seconds"` or `"screenshot in 5 seconds"` to capture tooltips and dropdown menus.
- ✂️ **Selection Cropping**: Say `"screenshot area"` to trigger macOS crosshairs and drag-select custom regions.
- 🗣️ **Optional Spoken Confirmation**: Hear natural voice feedback (e.g. *"Window 1 captured"*).
- 🚀 **100% Native Swift**: Zero Python/pip dependencies, no heavy virtualenvs, instant launch, negligible battery impact.

---

## 🔢 Window Numbering System (`snap1`, `snap2`, `snap3`...)

VoiceShot numbers application windows from front to back across connected displays. A window that's fully covered or off-screen gets no number. A partially visible window gets its badge on the part you can see.

```
  ┌───────────────────────┐
  │ [1] Frontmost Window  │ (e.g. Safari / Active App)
  └───────────────────────┘
         ┌───────────────────────┐
         │ [2] Window Behind #1  │ (e.g. Terminal)
         └───────────────────────┘
                ┌───────────────────────┐
                │ [3] Background Window │ (e.g. VS Code / Slack)
                └───────────────────────┘
```

### Visual Window Badges

Say **“tags,” “nums,” “badges,”** or **“labels”** to show window numbers. Each also works with “show,” as in **“show tags.”** You can still say **“show numbers”** or press `Cmd + Shift + N`.

1. VoiceShot places a badge on the exposed part of each numbered window.
2. The number assignments last four seconds, so you can capture more than one numbered window.
3. Say the badge number on its own, such as “three,” to capture that window. You can also say “snap three” at any time.

---

## 🗣️ Voice Commands Reference

| Voice Command | Action Description | Target |
| :--- | :--- | :--- |
| **`"snap1"`** / **`"screenshot 1"`** | Captures Window #1 | Active frontmost window |
| **`"snap2"`** / **`"screenshot 2"`** | Captures Window #2 | Window directly behind #1 |
| **`"snap3"`** / **`"screenshot 3"`** | Captures Window #3 | Third visible window |
| **`"snap4"`** through **`"snap10"`** | Captures the window with that number | Subsequent visible windows |
| **`"tags"`** / **`"nums"`** / **`"show tags"`** / **`"show numbers"`** | Shows numbered badges | Visible windows |
| **`"screenshot Safari"`** *(or Chrome, Slack, etc.)* | Captures that application's front window | Named Application |
| **`"display 1"`** / **`"screen 1"`** | Captures full primary display | Display 1 |
| **`"display 2"`** / **`"screen 2"`** | Captures external secondary monitor | Display 2 |
| **`"screenshot area"`** / **`"crop screenshot"`** | Activates interactive drag-selection crosshair | Custom Crop Rect |
| **`"screenshot text"`** / **`"copy text"`** | Extracts on-screen text via Vision OCR | Clipboard (as String) |
| **`"screenshot in 3 seconds"`** | Waits for 3-second countdown before capture | All Displays |
| **`"take screenshot"`** / **`"screenshot"`** | Full-screen capture across all monitors | All Displays |

Say “snap one” for `snap1`, “snap two” for `snap2`, and so on. If a window number is unavailable, say “show numbers” to see the current assignments.

VoiceShot checks recognized phrases against a local command dictionary. It can interpret common sound-alikes such as “snap tree” and small transcription errors such as “snap Safary.” When nearby matches point to different actions, it waits for a clearer command.

---

## 🚀 Quick Start & Installation

### Install from GitHub Releases

On an Apple Silicon Mac with macOS 12 or later, open the disk image and drag the **VoiceShot** icon onto **Applications**. Eject the disk image, then open VoiceShot from Applications. Release builds are ad-hoc signed and may require approval in macOS Privacy & Security on first launch. [Download VoiceShot for Mac](https://github.com/Kaphleamrit/voiceshot/releases/latest/download/VoiceShot-macOS-arm64.dmg), [Apple’s first-launch instructions](https://support.apple.com/en-us/102445)

After installing the first release that includes the updater, click **Update** in the popup. VoiceShot downloads and verifies the release, installs it, and relaunches automatically. **Later** dismisses the popup, and **Don’t ask me again** turns off automatic checks. You can still use **Check for Updates…** or turn **Automatically Check for Updates** back on from the menu bar.

### Launch from source

Run the launcher script to start VoiceShot with the **Live Monitor & Preferences** dashboard:

```bash
cd /Users/kaphley/.gemini/antigravity/scratch/voiceshot
./start.sh --monitor
```

### Install from source

To install VoiceShot into your macOS Applications folder so it appears in Spotlight (`Cmd + Space` ➔ `VoiceShot`):

```bash
cd /Users/kaphley/.gemini/antigravity/scratch/voiceshot
./install.sh
```

The install and launch scripts rebuild the local app when its sources are newer than the executable.

---

## 🔐 First-Time Permissions

When launched for the first time, macOS will request privacy permissions:

1. **Microphone Access**: To listen continuously for voice commands.
2. **Speech Recognition**: For Apple's on-device/system speech-to-text service.
3. **Screen Recording**: To capture display and window pixels.

> **Tip**: If prompted or if permissions were previously denied, navigate to:
> **System Settings > Privacy & Security** ➔ Enable **Microphone**, **Speech Recognition**, and **Screen Recording** for **VoiceShot** (or click *"Open Privacy Settings"* in the VoiceShot Preferences window).

---

## 🛠️ Menu Bar & Keyboard Shortcuts

Click the camera icon (`📸`) in the macOS menu bar to access quick controls:

| Action | Menu Item | Global Shortcut |
| :--- | :--- | :--- |
| **Show Window Numbers** | 🏷️ Show Window Numbers On Screen | `Cmd + Shift + N` |
| **Capture Window 1** | 🪟 Capture Window 1 (`snap1`) | `Cmd + Shift + 1` |
| **Capture Window 2** | 🪟 Capture Window 2 (`snap2`) | `Cmd + Shift + 2` |
| **Capture Window 3** | 🪟 Capture Window 3 (`snap3`) | `Cmd + Shift + 3` |
| **Capture All Displays** | 📸 Capture All Displays | `Cmd + Shift + S` |
| **Capture Selection Area** | ✂️ Capture Selection Area | `Cmd + Shift + 4` |
| **Extract Text (OCR)** | 📝 Extract Text (OCR) | `Cmd + Shift + T` |
| **Toggle Local Saving** | Save Screenshots Locally (off by default) | — |
| **Toggle Clipboard Copy** | 📋 Copy to Clipboard | — |
| **Toggle Floating Preview** | 🖼️ Floating Preview | — |
| **Toggle Voice Feedback** | 🗣️ Voice Feedback | — |
| **Open Preferences** | ⚙️ Preferences & Live Monitor... | `Cmd + ,` |
| **Quit** | Quit VoiceShot | `Cmd + Q` |

---

## ⚙️ Preferences & Customization

Open the Preferences window (`Cmd + ,`) to customize:

- **Automatic Listening Breaks** are on by default. After 15 minutes without a recognized VoiceShot command, the microphone stays active for “wake up.” Say it on its own or click **Resume Listening** to return to voice commands. Uncheck **Take a listening break after 15 minutes of inactivity** to keep listening for commands continuously.
- **Save Location**: Change destination to `~/Desktop`, `~/Pictures/Screenshots`, or any custom folder.
- **Copy to Clipboard**: When local saving is enabled, choose whether to also copy the image.
- **Floating Preview Thumbnail**: Toggle CleanShot-style floating preview in bottom-right corner (Default: `ON`).
- **Spoken Voice Confirmation**: Toggle audio speech feedback like *"Window 1 captured"* (Default: `OFF`).
- **Camera Shutter Sound**: Toggle native camera audio effect (Default: `ON`).
- **Screen Flash Effect**: Smooth transient white screen flash when captured (Default: `ON`).
- **Desktop Notifications**: System banners with target detail & reveal action (Default: `ON`).
- **Default Delay**: Set a standing countdown delay (0s, 0.5s, 1s, 2s, 3s, 5s).
- **Custom Trigger Phrases**: Add or modify recognized phrases.

---

## 📁 Architecture & Source Tour

```
voiceshot/
├── VoiceShot.app/             # Compiled & signed macOS application bundle
│   └── Contents/
│       ├── MacOS/VoiceShot    # Native ARM64 binary executable
│       ├── Resources/         # AppIcon.icns & bundle resources
│       └── Info.plist         # Privacy strings & LSUIElement agent config
├── Sources/
│   ├── main.swift             # App entry point, activation policy & CLI flags
│   ├── AppDelegate.swift      # Menu Bar status item, menus & global shortcuts
│   ├── WindowManager.swift    # Quartz window inspection & floating badge overlays
│   ├── SpeechRecognizer.swift # Streaming audio engine & continuous trigger parser
│   ├── ScreenshotManager.swift# Screencapture runner, Vision OCR, flash & alerts
│   ├── FloatingPreview.swift  # Floating thumbnail quick-action overlay
│   ├── PreferencesManager.swift# UserDefaults settings persistence
│   └── MonitorWindow.swift    # AppKit GUI dashboard & live audio visualizer
├── Tests/
│   └── AutomatedTests.swift   # Comprehensive unit & streaming test suite
├── Resources/
│   └── AppIcon.icns           # High-resolution macOS application icon
├── Info.plist                 # Bundle metadata, entitlements & permissions
├── build.sh                   # Compiles Swift sources into VoiceShot.app bundle
├── start.sh                   # Launches VoiceShot with optional flags
├── install.sh                 # Installs VoiceShot into ~/Applications
└── README.md                  # Complete documentation
```

### Key Technical Implementations

1. **Continuous Non-Stop Speech Pipeline (`SpeechRecognizer.swift`)**:
   VoiceShot gives macOS Speech a vocabulary of commands and app names. The local dictionary uses an exact lookup first and a precomputed index for nearby phrases. Badge commands and complete countdown instructions can act on a partial transcription. Other captures wait briefly for a target or countdown to come through.

2. **On-Device Machine Vision OCR (`ScreenshotManager.swift`)**:
   Uses Apple's `VNRecognizeTextRequest` (`recognitionLevel = .accurate`, `usesLanguageCorrection = true`) to perform fast, 100% on-device text transcription directly from captured pixels.

3. **Window Boundary Math (`WindowManager.swift`)**:
   Converts top-left Quartz coordinates (`CGWindowBounds`) into bottom-left Cocoa coordinates (`NSScreen`) to accurately place floating badge overlays over each window's title bar.

---

## 🔨 Development & Automated Testing

### Building from Source

To compile all Swift files, generate the application bundle, and ad-hoc code sign:

```bash
cd /Users/kaphley/.gemini/antigravity/scratch/voiceshot
./build.sh
```

### Running Automated Test Suite

The automated suite checks window discovery and voice parsing. Run it in a macOS desktop session with at least one eligible window open.

```bash
cd /Users/kaphley/.gemini/antigravity/scratch/voiceshot
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swiftc \
  Sources/PreferencesManager.swift \
  Sources/FloatingPreview.swift \
  Sources/WindowManager.swift \
  Sources/ScreenshotManager.swift \
  Sources/VoiceCommandDictionary.swift \
  Sources/SpeechRecognizer.swift \
  Tests/AutomatedTests.swift \
  -o /tmp/run_tests && /tmp/run_tests
```

### Publishing a release

Set up the Sparkle signing key once. Run the commands below on a Mac with the GitHub CLI authenticated for this repository. Back up the signing key securely and use the same key for subsequent releases.

```bash
(
  set -e
  sparkle_dir="$(bash scripts/fetch-sparkle.sh)"
  "$sparkle_dir/bin/generate_keys" --account voiceshot
  key_file="$(mktemp)"
  trap 'rm -f "$key_file"' EXIT
  "$sparkle_dir/bin/generate_keys" --account voiceshot -x "$key_file"
  gh secret set SPARKLE_PRIVATE_KEY --repo Kaphleamrit/voiceshot < "$key_file"
)
```

Push a new stable version tag such as `v1.2.0` on the commit you want to release. GitHub Actions publishes the drag-to-Applications disk image for first installs alongside the signed ZIP and feed for Sparkle updates. Local source builds have the update menu disabled until a Sparkle public key is configured. [Sparkle publishing guide](https://sparkle-project.org/documentation/publishing/)

---

## ❓ Troubleshooting

| Issue | Cause | Solution |
| :--- | :--- | :--- |
| **"Permission Required" badge** | Microphone or Speech access denied | Open **System Settings > Privacy & Security** and enable Microphone and Speech Recognition for VoiceShot. |
| **Black screenshot or missing window** | Screen Recording permission missing | Enable Screen Recording for VoiceShot in **System Settings > Privacy & Security > Screen Recording**. |
| **Speech not recognized** | Input device muted or wrong mic | Open **Preferences & Live Monitor** (`Cmd + ,`) and speak to verify the **Mic: Level Bar** bounces. |
| **Window #2 captures wrong app** | Window order changed | Say **"show numbers"** to flash the current numbers on your windows, or click **🔄 Refresh** in Preferences. |

---

## 📄 License

Created with Swift & AppKit for macOS. Feel free to customize and extend for your own personal or commercial workflows!
