# FancyMacZones

A FancyZones-style window manager for macOS. Define zones per display, hold
**Shift** while dragging a window, and drop it into a zone to resize it to fit.

- Custom zone layouts built in a visual editor (split, delete, drag to resize)
- Adjustable outer margin and gap between zones
- Windows glide into zones, and return to their old size when dragged back out
- Per-display layouts, including portrait monitors (rows by default)
- Lives in the menu bar; no Dock icon unless a window is open

Requires macOS 14 or later.

## Build and install

```bash
scripts/build-app.sh --install
```

This builds `build/FancyMacZones.app`, copies it to `/Applications`, and launches it.
Run `scripts/build-app.sh` without `--install` to only build.

On first launch macOS asks for **Accessibility** permission (System Settings →
Privacy & Security → Accessibility). FancyMacZones needs it to see and move other
apps' windows. Snapping starts as soon as it is granted; no restart needed.

The build is signed with your first "Apple Development" identity (override
with `SIGN_IDENTITY=...`). Keep the identity stable: macOS ties the permission
to the signature, so an ad-hoc (`SIGN_IDENTITY=-`) build has to be re-granted
after every rebuild.

## Use

| Action | How |
| --- | --- |
| Snap a window | Start dragging its title bar, hold **Shift**, release over a zone |
| Span several zones | While snapping, hold the cursor in the gap between zones; every zone within the span distance lights up and the window fills them all |
| Cancel a snap mid-drag | Let go of Shift before releasing the mouse |
| Unsnap a window | Drag it out of its zone; it returns to its pre-snap size |
| Pick a layout for a display | Menu bar icon → choose under that display's name |
| Edit layouts | Menu bar icon → **Edit Zones…** |
| Change gaps, snap key, animation, size restore | Menu bar icon → **Settings…** (gaps are also in the editor) |

### Zone editor

- Click a zone to select it, then use the buttons inside it or along the bottom:
  **Split Columns**, **Split Rows**, **Even Out** (equal sizes for it and its
  neighbours), **Delete** (⌘⌫).
- Drag the gap between two zones to resize them.
- Right-click a zone for the same actions.
- The canvas is drawn to scale for the display picked at the top right, gaps
  included. **Use on This Display** assigns the layout; **Preview on Screen**
  flashes the zones on the real display for two seconds.
- **+** adds a layout from a preset. Layouts are proportional, so one layout
  works on displays of any size.

### Multiple displays

Each display has its own layout. While you drag, the zones of the display under
the cursor are shown, so you can drag a window from one monitor into a zone on
another. Displays you haven't assigned a layout get the first columns layout if
they're landscape, or the first rows layout if they're portrait.

### Spanning zones

With **Span zones when dragging near the gap between them** on (the default),
any zone within the span distance (20 pt by default, adjustable from 4 to 64)
of the cursor is included. With the cursor in a gap, the zones on both sides light
up; at the corner of a 2×2 grid, all four do. A dashed outline shows the area
the window will fill. If the spanned zones don't form a rectangle, the zones
needed to fill one are included as well.

### Restore and animation

When you drag a snapped window, it goes back to the size it had before it was
snapped (animated, if animation is on), with the cursor kept at the same spot along the title bar. If you
resized it yourself after snapping, it's left alone. Turn this off with
**Restore size when dragged out of a zone**.

Snapping animates over 200 ms by default (adjustable from 100 to 500 ms, or off).
macOS has no API to animate another app's window, so FancyMacZones resizes it in
small steps; heavy apps (Xcode, browsers) may look a little choppy.

## Config

Stored at `~/Library/Application Support/FancyMacZones/config.json` and saved
automatically. It's plain JSON, so you can back it up or edit it by hand
(set `FANCYMACZONES_CONFIG=/path/to/file.json` to use a different file).
On first launch after the rename from MacZones, the old config is copied over
from `~/Library/Application Support/MacZones/`.

## Develop

```bash
swift test
```

`Sources/ZonesCore` holds the layout tree, gap geometry, and config. It's pure
Swift with unit tests. `Sources/FancyMacZones` is the AppKit/SwiftUI app: event
monitoring, Accessibility window control, overlay, editor, and settings.

```bash
swift run FancyMacZones --snapshot /tmp/fancymaczones-snaps
```

This renders the overlay, the editor canvas for every default layout
(landscape and portrait), and the editor and settings windows to PNGs, then
quits. It needs no permissions and doesn't touch your config. Native controls
(buttons, pickers) show up as placeholders in these images.

## Known limits

- Apps with a minimum window size, or that resize in fixed steps (Terminal),
  may not fill a zone exactly.
- Some apps (Ghostty, for one) override resizes made mid-drag; the restored size then lands when you release the mouse.
- Full-screen windows and windows of apps that don't support Accessibility
  can't be snapped.
- Not sandboxed, so it can't ship on the Mac App Store.

## License

[MIT](LICENSE)
