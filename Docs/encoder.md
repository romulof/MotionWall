# The encoder

MotionWall always writes HEVC Main 10 through the hardware encoder, because only that encoder writes the temporal layers the unlock animation needs (see [temporal-layers.md](temporal-layers.md)).

## Pipeline

```
decode → VideoToolbox super resolution 4× → Lanczos to the output size → VideoToolbox frame rate conversion to 120 fps → HEVC
```

Each VideoToolbox stage runs only when its option is on. Upscaling comes before interpolation because the upscaler is the slow stage, about 0.4 s per 720p frame on an M5: run first, it processes only the source frames instead of five times as many interpolated ones, and it never sharpens interpolation mistakes.

The super-resolution scaler works only at 4× and accepts video up to 1920×1080. It needs macOS 26 and downloads its model the first time, which the app shows as "Downloading the upscaling model…". It is fed linear light: given BT.709-encoded frames it darkens them by about 2%; with linear input the difference to Lanczos drops to about 1%.

## Output resolution

The app keeps the source's aspect ratio. The output is the source size, or four times it with **Upscale** on, shrunk to fit 4K: the long side at most 3840 and the short side at most 2160, whichever way round the video is.

| Source | Upscale | Output |
|---|---|---|
| 854×480 | on | 3416×1920 (4× fits, nothing more) |
| 1280×720 | on | 3840×2160 (5120×2880 shrunk) |
| 1920×1080 | on | 3840×2160 (7680×4320 shrunk) |
| 1280×720 | off | 1280×720 |
| 7680×4320 | not offered | 3840×2160 |

## Bitrate

The bitrate is a target passed to `kVTCompressionPropertyKey_AverageBitRate`, and the encoder hits it whatever the frame rate.

The app's Bitrate field and the CLI's `--bitrate` default, both in kbit/s, start from the same suggestion, `WallpaperRequest.suggestedBitrateKbps` in `Sources/MotionWallCore/BitrateSuggestion.swift`:

```
suggested = source kbit/s × codec factor × resolution factor × frame factor
```

rounded to the nearest 100 kbit/s, at least 100. When the source does not report a bitrate, the codec part is replaced by 12,000 kbit/s, which is already an HEVC figure.

### Codec factor

The source's bitrate says how many bits its codec needed for that picture. HEVC needs a different amount for the same quality, so the source bitrate is first converted into HEVC kbit/s.

| Source codec | Factor | Why |
|---|---|---|
| HEVC, and anything not listed | 1.0 | Same codec, or unknown |
| AV1 | 1.3 | About 30% more efficient than HEVC, so HEVC needs more bits |
| H.264 | 0.6 | HEVC needs about half the bits; 0.6 leaves room for the hardware encoder, which is less efficient than software ones |
| MPEG-2, MPEG-1, MPEG-4 Part 2, H.263 | 0.4 | Older codecs, well over twice HEVC's cost |
| ProRes, Motion JPEG, DV | 0.1 | Intra-frame codecs that spend most of their bits on near-lossless editing quality |

The codec is read from the video track's format description (`VideoSource.codec`).

### Resolution factor

More pixels need more bits, but not proportionally:

```
resolution factor = (output pixels ÷ source pixels) ^ 0.8
```

A 720p source upscaled to 4K has 9× the pixels and gets 5.8× the bitrate; one upscaled from 1080p to 4K gets 3×. Shrinking lowers the bitrate the same way.

The 0.8 comes from encoding a 720p clip and its 4× upscale to 1440p at several bitrates. At 1,500 kbit/s for the 720p, the 1440p needed about 4,600 kbit/s for the same quality: three times the bits for four times the pixels, and 4^0.8 ≈ 3. The exponent grows with the quality aimed for (0.63 at 1,000 kbit/s, above 1 at 2,000 kbit/s), so 0.8 is a middle value.

### Frame factor

With **Interpolate to 120 fps** on, the output has more frames than the source, while the bitrate stays a per-second budget. Spreading the same bits over more frames lowers the quality of every frame. Generated frames are predicted from their neighbours, so each one costs much less than a source frame:

```
added frames per source frame = 120 ÷ source fps − 1
frame factor = 1 + added frames per source frame × 0.25
```

| Source fps | Added frames per source frame | Frame factor |
|---|---|---|
| 24 | 4 | 2.0 |
| 25 | 3.8 | 1.95 |
| 30 | 3 | 1.75 |
| 60 | 1 | 1.25 |
| 120 | 0 | 1.0 (the option is hidden) |

With the option off the frame factor is 1.

#### Where 0.25 comes from

A 41-second 720p clip at 24 fps was encoded at several bitrates and each output compared with a very-high-bitrate encode of itself (luma PSNR, higher is better):

| Output | Bitrate | PSNR |
|---|---|---|
| 24 fps | 2 Mbit/s | 51.1 dB |
| 120 fps | 2 Mbit/s | 49.0 dB |
| 120 fps | 4 Mbit/s | 51.4 dB |
| 120 fps | 6 Mbit/s | 52.9 dB |
| 120 fps | 10 Mbit/s | 54.5 dB |

Twice the bitrate brought the 120 fps output back to the 24 fps quality. Five times the frames for twice the bits means the four added frames together cost one source frame, a quarter each.

## Examples

| Source | Codec | Resolution | Frame | Suggested |
|---|---|---|---|---|
| 30 fps H.264 at 2,000 kbit/s, no upscale, 120 fps on | 0.6 | 1.0 | 1.75 | 2,000 × 0.6 × 1.75 = 2,100 kbit/s |
| 24 fps 720p H.264 at 1,552 kbit/s, no upscale, 120 fps off | 0.6 | 1.0 | 1.0 | 931 → 900 kbit/s |
| 24 fps 720p H.264 at 1,552 kbit/s, upscaled to 4K, 120 fps on | 0.6 | 5.8 | 2.0 | 10,802 → 10,800 kbit/s |
| 30 fps 1080p HEVC at 8,000 kbit/s, upscaled to 4K, 120 fps on | 1.0 | 3.03 | 1.75 | 42,440 → 42,400 kbit/s |
| 120 fps ProRes 422 HQ at 424,590 kbit/s, no upscale | 0.1 | 1.0 | 1.0 | 42,459 → 42,500 kbit/s |

## In the app

The Bitrate field takes the suggestion when a video loads. Ticking or unticking **Upscale** or **Interpolate to 120 fps** replaces it with the new suggestion, unless you have typed a different value, which is kept.

## Limits

- The 0.25 comes from one low-motion clip. Fast motion and scene cuts make generated frames harder to predict and may need more.
- The 0.8 also comes from one clip, and from upscaled frames, which hold less fine detail than footage shot at that resolution.
- The codec factors are typical figures from the literature, not measured on this encoder.
