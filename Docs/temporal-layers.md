# Why temporal layers matter

macOS plays an aerial on the lock screen, then **slows it to a stop** when you
unlock. That deceleration is driven by HEVC temporal sub-layers: the player drops
the enhancement layer to play fewer frames.

Without them the desktop goes black on unlock, and the log reports:

```
Switching player state .beginRampingDown
Error handling sample: Error Domain=WallpaperExtensionKit.VideoSampleReadingErrors Code=4
VideoPlayerLayer failed to acquire next sample
FlushPrimaryAndFaderLayers
```

A correct file carries these sample groups in `stbl`:

| Atom | Meaning |
|---|---|
| `tscl` | which temporal layer each frame belongs to |
| `tsas` | where a player may switch layers |

Check any file with `ffprobe`-adjacent tooling, or by reading the `sgpd` boxes.

## Why not ffmpeg

`ffmpeg` cannot write `tscl`/`tsas` sample groups at all. No muxer flag enables them.

`AVAssetWriter` refuses the relevant property for HEVC:

```
Compression property BaseLayerFrameRateFraction is not supported for video codec type hvc1
```

So this tool drives `VTCompressionSession` directly and sets three properties that
are **not declared in the SDK headers**. They were found by calling
`VTSessionCopySupportedPropertyDictionary` on a live session:

```
NumberOfTemporalLayers = 2
TemporalIDNestingFlag  = true
BaseLayerFrameRate     = fps / 2
```

`NumberOfTemporalLayers` is the one that emits the atoms. It is supported only by the
hardware encoder, `com.apple.videotoolbox.videoencoder.ave.hevc`. The tool requires a
hardware encoder and fails early with a clear message when one is unavailable.

## Properties that turned out not to matter

Frame rate, bit depth, colour range, audio track, duration, resolution, and the
`mvhd` timescale were each tested against a working reference and ruled out.
