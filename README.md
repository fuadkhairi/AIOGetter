# AIOGetter

A native macOS app for downloading videos from social media links. Paste a link, pick a format, and AIOGetter runs [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) on your Mac, shows live progress, and saves the file to your `~/Downloads` folder.

Built with SwiftUI and `@Observable`. There are no Python scripts, no web servers and no accounts. Everything runs locally.

## Features

- Download from TikTok, Instagram Reels, YouTube (including Shorts), X/Twitter, Reddit, Pinterest and the many other sites `yt-dlp` supports
- **Paste & Download** button, plus a banner that offers to download a supported link when you copy one
- Format choices: Best (MP4), 1080p, 720p, or Audio only (MP3)
- Live progress card with percent, size, speed and ETA, and a Stop button
- Download queue (one at a time)
- Completed list that survives relaunches, with **Show in Finder** and **Play** buttons
- Optional menu bar item for quick paste-and-download
- Settings screen that checks for `yt-dlp` and `ffmpeg` and shows the install command if either is missing
- Clear error messages for private videos, unsupported links, rate limits and missing dependencies

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15 or later, to build
- [Homebrew](https://brew.sh) packages `yt-dlp` and `ffmpeg`:

```bash
brew install yt-dlp ffmpeg
```

`yt-dlp` is required. `ffmpeg` is needed for MP3 extraction and for merging separate video and audio streams (1080p and above, and best quality on some sites). Without it, AIOGetter falls back to single-file MP4 downloads.

## Build and run

```bash
git clone https://github.com/fuadkhairi/AIOGetter.git
cd AIOGetter
open AIOGetter.xcodeproj
```

Select your team under **Signing & Capabilities** if Xcode asks, then press **Run** (⌘R).

To build a Release app from the command line:

```bash
xcodebuild -project AIOGetter.xcodeproj -scheme AIOGetter -configuration Release \
  -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Release/AIOGetter.app
```

> **Note:** The app is not notarized. If macOS blocks it on first launch, right-click the app and choose **Open**.

## Usage

1. Copy a video link and click **Paste & Download**, or paste it into the field and press Return.
2. Pick a format from the selector above the list.
3. Watch progress in the card. Click **Stop** to cancel.
4. When it finishes, the video appears under **Completed**. Use the folder icon to reveal it in Finder, or the play icon to open it.

Open **Settings** (⌘,) to see where `yt-dlp` and `ffmpeg` were found, set a custom `yt-dlp` path, change the default format, or turn the menu bar item and clipboard detection on or off.

Sites change often. If a download starts failing, update the tool:

```bash
brew upgrade yt-dlp
```

## How it works

| Piece | Details |
| --- | --- |
| Finding tools | Checks `/opt/homebrew/bin`, `/usr/local/bin` and a few other locations, then asks a login shell (`command -v`). GUI apps don't inherit your shell `PATH`, so this is done explicitly |
| Running `yt-dlp` | Foundation `Process` and `Pipe`, wrapped in an `AsyncThrowingStream` that delivers `stdout` and `stderr` line by line, in order |
| Progress | Parses `yt-dlp`'s `--newline` output with a regex for percent, size, speed and ETA, and reads destination paths to find the final file |
| Cancelling | Stopping a download terminates the `yt-dlp` process |
| Output | `~/Downloads/<title>.<ext>`, with long titles shortened |
| State | MVVM with `@Observable` models and a single downloader service shared through the SwiftUI environment |

The app runs **without App Sandbox**, because a sandboxed app can't launch Homebrew binaries. This means it can't be distributed through the Mac App Store.

## Project structure

```
AIOGetter/
├── AIOGetter.xcodeproj
├── AIOGetter/
│   ├── App/LocalMediaDownloaderApp.swift     # @main, window, menu bar item, settings scene
│   ├── Models/
│   │   ├── DownloadTask.swift                # task, state, quality, history record
│   │   └── AppSettings.swift                 # persisted preferences
│   ├── Services/
│   │   ├── ProcessRunner.swift               # Process wrapper, tool locator
│   │   └── VideoDownloaderService.swift      # queue, yt-dlp arguments, output parser, history
│   ├── Views/
│   │   ├── MainView.swift
│   │   ├── DownloadProgressView.swift
│   │   ├── HistoryListView.swift
│   │   ├── SettingsView.swift
│   │   └── MenuBarView.swift
│   ├── Utilities/PasteboardHelper.swift      # clipboard and URL detection
│   └── Assets.xcassets                       # app icon
└── AIOGetterTests/                           # parser, runner and service tests
```

## Tests

```bash
xcodebuild -project AIOGetter.xcodeproj -scheme AIOGetter -destination 'platform=macOS' \
  test -only-testing:AIOGetterTests
```

The tests cover output parsing, format arguments, URL detection, the process runner (streaming and cancellation) and the whole download flow, using a fake `yt-dlp` script. They don't need `yt-dlp` installed.

## Responsible use

Only download content you own or have permission to save, and follow the terms of service of the sites you use. AIOGetter is a front end for `yt-dlp` and is not affiliated with it or with any of the supported sites.

## License

Add a license of your choice (for example MIT or Apache 2.0) before publishing.
