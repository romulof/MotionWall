<p align="center">
  <img src="Design/AppIcon-256.png" width="128" height="128" alt="MotionWall icon">
</p>

<h1 align="center">MotionWall</h1>

<p align="center">Turn any video into a macOS animated wallpaper and install it into System Settings → Wallpaper.</p>

MotionWall is a Mac app with a command-line tool inside it. Both do the same job: encode the video the way macOS needs it, make the thumbnail tile, and add the wallpaper to your library.

## Getting started

You need macOS 13 or later and a Mac with a hardware HEVC encoder. Every Apple silicon Mac has one. So does any Intel Mac with Quick Sync. MotionWall checks for it and stops with a clear message when it is missing.

Download `MotionWall-<version>.zip` from the [latest release](https://github.com/romulof/MotionWall/releases/latest), unzip it and move `MotionWall.app` to `/Applications`. The app is not notarized, so macOS blocks the first launch: right-click it and choose Open, or allow it under System Settings → Privacy & Security.

To build it yourself you also need Xcode:

```
git clone git@github.com:romulof/MotionWall.git
cd MotionWall
xcodebuild -project MotionWall.xcodeproj -scheme MotionWall -configuration Release -derivedDataPath .build/xcode build
```

The app lands at `.build/xcode/Build/Products/Release/MotionWall.app`. Or open `MotionWall.xcodeproj` and press Run.

The CLI ships inside the app at `MotionWall.app/Contents/Helpers/motionwall`. It sits in `Helpers` rather than `MacOS` because `motionwall` and the app's own `MotionWall` executable would be the same file on a case-insensitive volume.

Install the app and put the CLI on your PATH:

```
cp -R .build/xcode/Build/Products/Release/MotionWall.app /Applications/
sudo ln -s /Applications/MotionWall.app/Contents/Helpers/motionwall /usr/local/bin/motionwall
```

Link the CLI rather than copying it: it loads `libMotionWallCore.dylib` from the app's `Contents/Frameworks`, so a copy outside the app cannot start.

To remove it later, delete the app and the link. Wallpapers you already installed stay in place.

## The app

Open MotionWall and drop a video on the window, or press Choose video…. Any format QuickTime can read works.

Once the video is in, the left side holds the settings and the right side shows the thumbnail tile and the Install button:

- **Name** and **Category** are what System Settings shows. The name starts as the file name, the category as `Custom`.
- **Width** and **Height** start empty, which means the source size. They scale independently, so setting only one changes the aspect ratio.
- **Frame rate** is the source's. MotionWall keeps every frame. **Interpolate to 120 fps**, on by default, adds frames in between with VideoToolbox frame rate conversion for a smoother unlock. It needs macOS 15.4 or later and is hidden when the source already runs at 120 fps or the Mac does not support it. The CLI keeps the source frame rate.
- **Bitrate**, in kbit/s, starts at the source's bitrate converted to HEVC, raised when 120 fps is on. Ticking the box updates the field unless you typed your own value. [Docs/encoder.md](Docs/encoder.md) has the math.
- **Thumbnail** picks the frame used for the tile. The preview on the right is the exact 642×390 image that gets installed.

To swap videos, drag another one over the window. Before you let go, it shows that file's name, size, frame rate and bitrate. Change… on the right does the same through a file picker.

Install shows its progress, asks before replacing one of your own wallpapers, and offers to open Wallpaper settings when it is done.

The window follows the system's light and dark appearance, and uses Liquid Glass on macOS 26 and later.

The app is not sandboxed: it writes into `~/Library/Application Support/com.apple.wallpaper` and restarts `WallpaperAgent`, and the sandbox forbids both.

## The CLI

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
| `--bitrate <kbps>` | no | source bitrate, converted to HEVC | Target bitrate in kbit/s, at least `100`. See [Docs/encoder.md](Docs/encoder.md). Falls back to `12000` when the source does not report one. |
| `--force` | no | off | Replace an existing wallpaper without asking. |

Width and height scale independently, as in the app: setting only one stretches the picture.

Example:

```
motionwall --input video.mp4 --name "My Wallpaper" --width 3840 --height 2160 --thumbnail-frame 200
```

## What it does

1. Reads the source and scales it with `CILanczosScaleTransform`.
    When the app's 120 fps option is on, VideoToolbox's frame rate converter interpolates the scaled frames onto a 120 fps grid.
2. Encodes HEVC Main 10 through `VTCompressionSession`, with temporal layers.
3. Extracts the chosen frame, centre-crops it to the 642×390 tile aspect.
4. Copies both files into `~/Library/Application Support/com.apple.wallpaper/aerials/`.
5. Adds or replaces the entry in `manifest/entries.json`, then restarts `WallpaperAgent`. When the manifest bundled with macOS has a newer `version`, MotionWall first rebuilds the file from it and carries your own categories and wallpapers over, because the wallpaper selector ignores an older downloaded manifest.

Output has no audio track. Apple's aerials have none either.

The temporal layers in step 2 are what make the unlock animation work. See [Docs/temporal-layers.md](Docs/temporal-layers.md) for why, and for why `ffmpeg` cannot produce such a file.

## Safety

- Apple categories are refused. A category is Apple's when its id is `dynamic-aerials` or its name key starts with `AerialCategory`. Both the raw key (`AerialCategoryLandscapes`) and the display name (`Landscapes`) are matched.
- Apple assets are refused. An asset is Apple's when its video URL is not `file://`.
- Replacing one of your own wallpapers asks first, in the app and in the CLI. `--force` skips the question in the CLI.
- `manifest/entries.json` is copied to `entries.json.bak` before the first write.

## Project layout

| Path | What it is |
|---|---|
| `Sources/MotionWallCore` | The encoder, thumbnail maker and wallpaper library code, built as `libMotionWallCore.dylib`, which the app and the CLI share. |
| `Sources/MotionWallCli` | The `motionwall` command-line tool. |
| `Sources/MotionWallApp` | The SwiftUI app, including the `AppIcon.icon` app icon. |
| `Design` | Source artwork for the icon. |
| `Docs` | Background reading. |

## Contributing

Commit messages and PR titles follow [Conventional Commits](https://www.conventionalcommits.org): `<type>(<scope>)!: <description>`, with type one of `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style` or `test`. CI rejects a pull request whose title or commits do not match, and builds the app with Xcode.

Releases are cut from those messages. On every push to `main`, [release-please](https://github.com/googleapis/release-please) keeps a release PR open with the next version and the changelog: `fix` bumps the patch, `feat` the minor, and `!` marks a breaking change. Merging that PR tags the release, publishes its notes, and attaches the built `MotionWall-<version>.zip`. `scripts/build-app.sh` is the build both workflows run.

## Docs

- [How the encoder picks a bitrate](Docs/encoder.md) — the codec and frame-rate factors behind the default bitrate, and the measurement they come from.
- [Why temporal layers matter](Docs/temporal-layers.md) — the HEVC sample groups macOS needs for the unlock animation, why the desktop goes black without them, why `ffmpeg` cannot write them, and which video properties turned out to be irrelevant.

## Licence

GPL v3. See [LICENSE](LICENSE).
