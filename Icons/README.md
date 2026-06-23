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

## Note on macOS "Liquid Glass"

The glass treatment here is **baked into the artwork**, so it renders on every
macOS version this app supports (deployment target is macOS 14). macOS 26
"Tahoe" adds *dynamic* Liquid Glass icons authored in Apple's **Icon Composer**
and shipped as a single `.icon` file — but that requires Xcode 26 and raising
the deployment target, so it's a deliberate future upgrade rather than the
default. If you go that route, export from Icon Composer and replace the
`AppIcon.appiconset` reference with the `.icon`; the artwork in
`HighRise iCons` is a good starting point for the Icon Composer layers.
