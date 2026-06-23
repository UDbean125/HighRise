# HighRise app icons

A one-command pipeline that turns your master artwork into app icons for
**macOS**, **iOS / iPadOS**, and **Windows**. It runs on a Mac and is the only
step that needs your artwork — the artwork itself is *not* committed here.

## 1. Generate

Your artwork lives at
`/Volumes/Satechi/HenSolutions/Apps/HighRise/HighRise iCons`. The icon source is
`HighRise App iCon 1280x768.jpg` (the skyline art). It's landscape, so the
script crops a square from it automatically:

```sh
ICONS="/Volumes/Satechi/HenSolutions/Apps/HighRise/HighRise iCons"
./Icons/make-icons.sh --macos "$ICONS/HighRise App iCon 1280x768.jpg"
```

`--ios`/`--win` fall back to the `--macos` master, so one flag does all three
platforms. For the Windows `.ico` you need ImageMagick once:
`brew install imagemagick`.

If the centered crop clips the skyline, choose which part to keep:

```sh
./Icons/make-icons.sh --macos "$ICONS/HighRise App iCon 1280x768.jpg" --crop left
```

(`--crop left|right|center|top|bottom`; anchors other than `center` need
ImageMagick.)

> The two `HighRise Icon …720.jpg` files are the wide **logo banners**
> (header/marketing art), not icon sources — don't feed those to the script.

**Which artwork goes where** (this matters — wrong framing looks broken):

| Platform | Wants | Note for the supplied art |
|---|---|---|
| **iOS / iPadOS** | full-bleed **opaque square** | the cropped skyline JPEG is ideal; OS rounds corners |
| **Windows** | full-bleed square | same as iOS |
| **macOS** | rounded "squircle" with **transparent margins** | a JPEG has no alpha, so you get a full square tile, not the padded squircle. For the classic look, supply a PNG-with-alpha master later |

Sources should ideally be **≥1024px** on the short side; `1280×768` crops to a
768px square, so the largest slots are mildly upscaled (the script warns).

## 2. What it produces

```
Icons/AppIcon-macOS.appiconset/   10 PNGs (16–512 @1x/@2x) + Contents.json
Icons/AppIcon-iOS.appiconset/     AppIcon-iOS-1024.png + Contents.json
Icons/windows/HighRise.ico        16/24/32/48/64/128/256 px
```

The two `.appiconset` folders are real Xcode asset catalogs — drop them straight
into a target.

## 3. Wiring macOS  (already done)

The macOS icon is **already wired** into the build:

* `project.yml` sets `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`
* `HighRise/Info.plist` sets `CFBundleIconName = AppIcon`
* `HighRise/Assets.xcassets/AppIcon.appiconset/` exists with declared slots but
  no images yet (so `actool` only warns — it never fails CI before the PNGs
  exist).

All that's left is to drop the generated PNGs into that catalog. The easiest way
is to pass `--install`, which copies the macOS set straight in:

```sh
./Icons/make-icons.sh --macos "$ICONS/HighRise App iCon 1280x768.jpg" --install
```

Then commit the PNGs and regenerate the project:

```sh
git add HighRise/Assets.xcassets/AppIcon.appiconset
xcodegen generate     # run from the repo root, matching ci.yml
```

(Without `--install`, copy `Icons/AppIcon-macOS.appiconset/*` into
`HighRise/Assets.xcassets/AppIcon.appiconset/` by hand.) XcodeGen auto-includes
the `.xcassets` because it's under the `HighRise` sources path, so no further
project change is needed.

## 4. Wiring iOS / iPadOS and Windows

* **iOS / iPadOS** — there's no iOS target in this repo yet. When one is added,
  copy `Icons/AppIcon-iOS.appiconset` into its asset catalog as
  `AppIcon.appiconset` and set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
  The single 1024 "universal" entry covers iPhone and iPad on Xcode 14+.
* **Windows** — use `Icons/windows/HighRise.ico` as the executable/installer
  icon (e.g. in your `.rc` file or packaging config for the Windows build).

## Liquid Glass via Icon Composer (upgrade path)

The current `.appiconset` bakes the glass look into static PNGs that work on
macOS 14+. To adopt Apple's *dynamic* Liquid Glass you author a single
`HighRise.icon` in **Icon Composer** (ships with Xcode 26). Good news verified
against Apple's docs: the `.icon` is **backward compatible** — `actool` emits
both a layered asset for macOS 26 / iOS 26 *and* a fallback `.icns` for older
systems, so you do **not** have to raise the deployment target; macOS 14–25
users just get the static icon.

What it takes:

1. **High-resolution, layered source art** (≥1024px, ideally separate
   foreground/background with transparency). The 265px JPEGs in `HighRise iCons`
   are far too small — re-export the skyline from the original design first.
2. **Author** `HighRise.icon` in Icon Composer on a Mac (it's a GUI app; can't
   be scripted in CI or from Linux).
3. **Add** `HighRise.icon` to the repo (e.g. `HighRise/HighRise.icon`) — it sits
   under the `HighRise` sources path so XcodeGen includes it.
4. **Switch the icon name**: in `project.yml` change
   `ASSETCATALOG_COMPILER_APPICON_NAME` from `AppIcon` to `HighRise` (the
   `.icon` file's name without extension), and remove `CFBundleIconName` /
   `AppIcon.appiconset` once the `.icon` is the source of truth.
5. **Build toolchain**: compiling a `.icon` requires **Xcode 26**. Update
   `.github/workflows/ci.yml` (and `release.yml`) to select Xcode 26 on the
   runner (e.g. `sudo xcode-select -s /Applications/Xcode_26.app`) or the build
   will fail even though the deployment target is unchanged.

Until all of that is in place, the static `.appiconset` remains the wired icon
so the app (and CI) keep working.

Sources: <https://useyourloaf.com/blog/adding-icon-composer-icons-to-xcode/>,
<https://developer.apple.com/documentation/Xcode/creating-your-app-icon-using-icon-composer>
