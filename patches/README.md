# Experimental Wine patch — viewport refresh race

## What it does

Wine renders a child window's OpenGL surface offscreen, then copies it to the
visible window with an X11 blit. Nothing guarantees the GPU has finished writing
that surface when the copy starts, so the copy can carry a stale image: the
viewport keeps showing the previous frame until something forces a full redraw.

Wine already contains the `glFinish` intended for exactly this case, in
`x11drv_surface_flush`. It is unreachable for a double-buffered application:
it is guarded by the `GL_FLUSH_PRESENT` flag, which is only ever set on the
front-buffer path. This patch makes the wait effective on both the GLX and EGL
swap paths.

## Measurements

Rhino 8.34, four viewports, 80 viewport refreshes per condition, on
Linux Mint 22.3 / Wine 11.16 staging / GTX 1060 with PRIME offload.

| Condition | What it waits for | Stale viewports |
|---|---|---|
| unpatched | nothing | 43.8 % |
| `XSync` | the X server, not the GPU | 17.5 % |
| 200 µs sleep | nothing, just time | 8.8 % |
| 3 ms sleep | long enough for the GPU | 0.0 % |
| **this patch (`glFinish`)** | **GPU completion** | **0.0 %** |

`XSync` is the discriminating measurement: it waits on the X server without
knowing anything about the GPU, and does *worse* than a blind wait of comparable
length. That rules out X request ordering and leaves GPU completion.

Redraw throughput was also measured, 200 full redraws of four viewports, three
runs per condition: **31.9 fps patched versus 29.1 unpatched**. The patch is not
merely free, it is about 10 % faster — an explicit wait avoids the presentation
queue backing up.

## Status and caveats

- Validated on **one machine only**, against Wine 11.16.
- Not submitted upstream. It has not been reviewed by Wine developers.
- The measurement scene was a single box; behaviour on heavy scenes is unverified.
- You do **not** need this patch for a working Rhino install. The Rhino-side
  workaround in `scripts/redraw_fix.py` addresses the same symptom without
  rebuilding Wine.

## Applying it

Requires building Wine from source — roughly 1 h 30 for the first build.

```bash
git clone --depth 1 --branch wine-11.16 https://gitlab.winehq.org/wine/wine.git
cd wine && patch -p1 < ../wine-glfinish-offscreen-present.patch
```
