# Jellotris

Seven familiar tetrominoes, two very different attitudes. Jelly squishes and
slides. Grumpy sandstone refuses to budge once placed. Fill horizontal bands
to clear them, then let the jelly tumble into the gaps. Quick cascades multiply
your score. A marbled swirl shader, glossy title, and drifting droplets set the mood.

## Play

Install [LÖVE 11.5](https://love2d.org/) and run this directory:

```sh
love .
```

Press **Enter** or click **Let's Jelly** to start. The window can be resized;
the play space keeps its aspect ratio.

| Key | Action |
| --- | --- |
| Left / Right or A / D | Slide the falling piece |
| Up / W / X | Rotate clockwise |
| Q / Z | Rotate counterclockwise |
| Down / S | Fall faster |
| Space | Slam the piece down |
| C / Shift | Hold / swap (once per piece) |
| P / Esc | Pause / resume |
| R | Restart |
| M | Mute / unmute |
| H / F1 | Show / hide controls and rules |

Help pauses an active game and returns to its previous state when closed. Escape
also closes help. The main screen keeps just the logo, board, score, queue, and hold.

Every **fifth new piece is stone**. It uses a single rigid body while falling,
with the same movement, rotation, slam, and hold controls as jelly. After placement,
it becomes a static obstacle: no gravity, sliding, rotation, or displacement from
other pieces. Row clears remove individual stone cells; surviving fragments stay
fixed even when unsupported. Stone previews have sandy textures and grumpy faces,
and hold preserves the material. Tune the frequency with `rock_interval` in
`jellotris/config.lua`.

This is a physics variation, so pieces move continuously and rotate against
their surroundings. A horizontal band clears when at least nine landed cells
cover 88% of its width for 0.2 seconds. This forgives little jelly seams without
letting overlapping cells count twice. Ticks beside the jar show each band's
coverage. There is no grid snapping: cleared gaps close under gravity.

Single/double/triple/quadruple clears award 100/300/500/800 points, multiplied by
level and cascade count. Another clear within three seconds increases the
cascade multiplier. Every eight cleared lines increases the level. A pile that
stays above the jar's lip, or blocks the next spawn, ends the run. Your best score is saved in LÖVE's
`jellotris` save directory. Losing window focus automatically pauses gameplay.

## Inside the jar

- `main.lua` connects LÖVE callbacks to the game and renderer.
- `jellotris/config.lua` contains physics, timing, and board tuning.
- `jellotris/softbody.lua` builds a shared 3 × 3 particle lattice per square.
  Box2D circle fixtures handle collision; damped distance springs resist stretch
  and shear. Local shape recovery and area pressure keep the jelly from folding
  flat under a heavy pile. Steering applies forces instead of teleporting the shape.
- `jellotris/game.lua` owns the fixed 120 Hz simulation, bag/hold lifecycle,
  material cadence, scoring, line removal, pause, and top-out.
- `jellotris/rock.lua` owns rigid falling bodies, static placement, and fixture removal.
- `jellotris/rows.lua` measures the union of landed-cell footprints per band.
- `jellotris/renderer.lua` draws meshes and the interface. `face.lua` draws
  expressions; `title.lua` animates the logo and its droplets.
- `assets/jelly.glsl` shades the mesh with rounded edges, wet highlights, and
  trapped bubbles. `assets/rock.glsl` shades chipped sandstone,
  `assets/background.glsl` draws the swirled ink, and `assets/title.glsl`
  adds animated sheen and bevels to the logo.
- `jellotris/audio.lua` synthesizes the sound effects in memory.

The game needs no external Lua packages, fonts, or sound files. Application icons
are included. Shader compilation failure falls back to plain meshes; unavailable
audio is tolerated.

## Build and package

Packaging needs **Python 3.9+**. GNU Make is optional; every target wraps
`python3 tools/build.py`. On Windows, use `py -3` in place of `python3`.
No Python packages or Lua compiler are required. Run commands from this directory.

```sh
make                 # list targets
make run             # play from source
make love            # dist/jellotris-0.2.0.love
make linux           # Linux archive using an installed LÖVE
make test-build      # packaging tests
make clean           # remove generated build/ and dist/
```

Set `VERSION=0.2.1` to change the output version. Output archives contain runtime
code and assets; they exclude tests, tools, saves, and editor files. The `.love`
archive is reproducible and runs on desktop platforms with LÖVE 11.5 installed:

```sh
python3 tools/build.py love --version 0.2.0
love dist/jellotris-0.2.0.love
```

Platform bundles follow the [official LÖVE distribution workflow](https://love2d.org/wiki/Game_Distribution).
Download matching **11.5** runtimes from the [official release](https://github.com/love2d/love/releases/tag/11.5).
The tools never download or modify your original runtime. Bundling uses a copy
and keeps its libraries and license files.

### Windows

Extract the official Windows ZIP, then point to the folder containing `love.exe`,
`love.dll`, and `license.txt`:

```sh
make windows LOVE_WINDOWS=/path/to/love-11.5-win64
# PowerShell, without Make:
py -3 tools/build.py windows --runtime "C:\tools\love-11.5-win64"
```

Output: `dist/jellotris-0.2.0-windows.zip`. Extract the whole ZIP and launch
`Jellotris.exe`; keep its DLLs beside it. The runtime determines the architecture.
The game window uses our PNG icon. To also replace the executable's Explorer icon,
use [rcedit](https://github.com/electron/rcedit) on Windows:

```powershell
py -3 tools/build.py windows --runtime "C:\tools\love-11.5-win64" --rcedit "C:\tools\rcedit-x64.exe"
```

Make accepts the equivalent `RCEDIT=/path/to/rcedit.exe`. The icon is applied before
fusing the game archive so the resource editor cannot strip the embedded game.

### macOS

Extract the macOS runtime and pass the `love.app` path:

```sh
make macos LOVE_MACOS=/path/to/love.app
# Without Make:
python3 tools/build.py macos --runtime /path/to/love.app --bundle-id org.jellotris.game
```

Output: `dist/jellotris-0.2.0-macos.zip`, containing `Jellotris.app` with the game,
native icon, and updated bundle metadata. Framework symlinks are preserved, and
the app does not claim ownership of all `.love` files. Use `BUNDLE_ID=your.bundle.id`
with Make to customize the identifier.

This produces an **unsigned bundle**. Test and sign it on macOS before distributing
it publicly; the packaging script does not perform signing or notarization. See
[Apple's distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases).
Native Windows/macOS execution must be verified on those platforms; the packaging
tests here validate archive contents and metadata using fixture runtimes.

### Linux

`make linux` produces `dist/jellotris-0.2.0-linux.tar.gz`. Extract it and run
`./jellotris`. This small bundle **requires an installed LÖVE 11.5** and works
from any directory, including paths with spaces.

To bundle the engine too, extract the official LÖVE AppImage in a separate folder
and point to the resulting `squashfs-root` directory:

```sh
chmod +x love-11.5-x86_64.AppImage
./love-11.5-x86_64.AppImage --appimage-extract
make linux LOVE_LINUX=/path/to/squashfs-root
# Without Make:
python3 tools/build.py linux --runtime /path/to/squashfs-root
```

This creates a tarball containing the runtime, a fused executable, launcher,
icon, and desktop-entry template. Users launch `./jellotris` after extraction;
they do not need LÖVE installed or FUSE to mount an AppImage. The runtime's
architecture and system-library requirements still apply. This target produces
a tarball, not a repackaged AppImage.

### Icon assets

`assets/icon.png` is the window icon; `assets/icon.ico` and `assets/icon.icns`
are native Windows/macOS containers. The icon is rendered from the actual jelly
and rock shaders, so it stays consistent with the game:

```sh
make icons
# Headless Linux:
ALSOFT_DRIVERS=null SDL_VIDEODRIVER=offscreen make icons
```

The editable composition is in `tools/icon.lua`. The build script renders sizes
from 16 to 1024 pixels and assembles the native containers without image libraries.

## Verify

```sh
love . --test
# Headless Linux:
ALSOFT_DRIVERS=null xvfb-run -a love . --test
# Without an X server, when SDL's offscreen driver is available:
ALSOFT_DRIVERS=null SDL_VIDEODRIVER=offscreen love . --test
make test-build
make smoke # render three frames of the packaged game, then exit
```

The integration suite uses actual LÖVE physics and shader compilation. It checks
bags, hold, steering, rotation, pause, collisions, row removal, scoring, fragment
cleanup, stone placement/hold/clears, help, saved scores, top-out, restart, and a
large soft-body pile. It writes two review
screenshots to `/tmp/jellotris-ready.png` and `/tmp/jellotris-playing.png`.
