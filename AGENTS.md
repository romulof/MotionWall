# AGENTS.md

MotionWall turns a video into a macOS animated wallpaper. It ships as `MotionWall.app` with the `motionwall` CLI inside. User-facing behaviour, flags and the install pipeline are in [README.md](README.md); why the HEVC temporal layers matter is in [Docs/temporal-layers.md](Docs/temporal-layers.md).

## Layout

- `Sources/MotionWallCore`: encoder, thumbnail maker, wallpaper library (`AerialLibrary`) and the `WallpaperInstaller` pipeline. Built as `libMotionWallCore.dylib`, which the app and the CLI share from `Contents/Frameworks`.
- `Sources/MotionWallCli`: the CLI. Embedded at `Contents/Helpers/motionwall`, never `Contents/MacOS`, where it would collide with `MotionWall` on a case-insensitive volume.
- `Sources/MotionWallApp`: the SwiftUI app and `AppIcon.icon`.
- `MotionWall.xcodeproj`: the only build definition. No SwiftPM. Its folders are synchronized, so new files need no project edit.

## Build

- `scripts/build-app.sh <version> [build-number]` builds, smoke-tests and zips the app into `.build/dist/`. It needs Xcode 26 or later.
- Swift 5 language mode, macOS 13 deployment target. Gate macOS 26 APIs such as Liquid Glass behind `#available`.
- Builds are ad-hoc signed with the hardened runtime off: library validation would reject the shared dylib. Turn it back on only together with Developer ID signing.

## Rules

- Never run a real install unless the user asks. It rewrites `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json` and restarts `WallpaperAgent`.
- Never call `WallpaperSelection.select` unless the user asks. It rewrites the user's wallpaper choice in `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`, an undocumented format, and only switches choices that already show an aerial.
- Never modify Apple's categories or assets. `AerialLibrary.isAppleOwned` defines ownership.
- Keep `AerialLibrary.load` rebasing onto the manifest bundled with macOS when that one has the higher `version`; the wallpaper extension ignores an older downloaded manifest.
- Keep the CLI's output and exit codes stable: usage errors exit 2, other failures exit 1.
- Core APIs block on semaphores. Call them off the main actor and off the cooperative pool, as `InstallModel` does.

## Commits and releases

- Commit messages and PR titles follow Conventional Commits. CI enforces it with `scripts/check-commit-messages.sh`.
- release-please cuts releases from those messages on `main`, and `.github/workflows/release.yml` attaches the built app. Never edit `CHANGELOG.md`, `.release-please-manifest.json` or the version by hand.
