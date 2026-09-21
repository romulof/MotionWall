# MotionWall

MotionWall turns any video into a macOS animated wallpaper and installs it into
System Settings → Wallpaper.

## Getting started

You need macOS 13 or later, the Xcode Command Line Tools, and a Mac with a
hardware HEVC encoder. Every Apple silicon Mac has one. So does any Intel Mac
with Quick Sync. MotionWall checks for it and stops with a clear message when it is
missing.

Build it:

```
git clone git@github.com:romulof/MotionWall.git
cd MotionWall
swift build -c release
```

The binary lands at `.build/release/motionwall`.

Put it on your PATH so you can call it from anywhere:

```
sudo cp .build/release/motionwall /usr/local/bin/
```

To remove it later, delete that file. Wallpapers you already installed stay in
place.

## Usage

```
motionwall --input <path> --name <name> [options]
```

| Flag | Required | Default | Meaning |
|---|---|---|---|
| `--input <path>` | yes | — | Source video. Any format AVFoundation can read. |
| `--name <name>` | yes | — | Wallpaper name shown in System Settings. |
| `--category <name>` | no | `Custom` | Section name in the wallpaper list. |
| `--thumbnail-frame <n>` | no | `1` | 1-based frame used for the tile image. |
| `--width <pixels>` | no | source width | Output width. Scaled with Lanczos. |
| `--height <pixels>` | no | source height | Output height. |
| `--bitrate <mbps>` | no | `12` | Target bitrate in Mbit/s. |
| `--force` | no | off | Replace an existing wallpaper without asking. |

Example:

```
motionwall --input video.mp4 --name "My Wallpaper" --width 3840 --height 2160 --thumbnail-frame 200
```

## What it does

1. Reads the source and scales it with `CILanczosScaleTransform`.
2. Encodes HEVC Main 10 through `VTCompressionSession`, with temporal layers.
3. Extracts the chosen frame, centre-crops it to the 642×390 tile aspect.
4. Copies both files into `~/Library/Application Support/com.apple.wallpaper/aerials/`.
5. Adds or replaces the entry in `manifest/entries.json`, then restarts `WallpaperAgent`.

Output has no audio track. Apple's aerials have none either.

The temporal layers in step 2 are what make the unlock animation work. See
[Docs/temporal-layers.md](Docs/temporal-layers.md) for why, and for why `ffmpeg`
cannot produce such a file.

## Safety

- Apple categories are refused. A category is Apple's when its id is
  `dynamic-aerials` or its name key starts with `AerialCategory`. Both the raw key
  (`AerialCategoryLandscapes`) and the display name (`Landscapes`) are matched.
- Apple assets are refused. An asset is Apple's when its video URL is not `file://`.
- Replacing your own wallpaper asks for confirmation unless `--force` is given.
- `manifest/entries.json` is copied to `entries.json.bak` before the first write.

## Docs

- [Why temporal layers matter](Docs/temporal-layers.md) — the HEVC sample groups
  macOS needs for the unlock animation, why the desktop goes black without them,
  why `ffmpeg` cannot write them, and which video properties turned out to be
  irrelevant.

## Licence

GPL v3. See [LICENSE](LICENSE).
