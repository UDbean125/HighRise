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

## Liquid Glass via Icon Composer (staged — `Icons/HighRise.icon`)

The dynamic Liquid Glass icon already exists: **`Icons/HighRise.icon`**, authored
in Icon Composer and **verified to build clean on Xcode 27** (`** BUILD
SUCCEEDED **` locally). It's `.icon` is **backward compatible** — `actool` emits
both a layered macOS 26/27 asset *and* an `.icns` fallback for older systems, so
no deployment-target change is needed.

It is **staged out of the build on purpose.** The blocker is the *build
toolchain version*, not the icon: GitHub's hosted runners currently top out at
**Xcode 26.3**, whose `actool` **crashes** compiling a 27-authored `.icon`
(`CompileAssetCatalogVariant … ibtoold … objc_exception_throw`). That would
break both `ci.yml` and `release.yml`. So the shipping icon stays the static
`AppIcon.appiconset` (also generated from the same 2048px master), keeping every
pipeline green with a crisp icon.

**Flip to Liquid Glass** once GitHub runners ship Xcode 27 GA (~fall 2026) — or
anytime for a *local* Xcode 27 build (CI would then go red until the runners
catch up):

```sh
git mv Icons/HighRise.icon HighRise/HighRise.icon      # into the built sources
git rm -r HighRise/Assets.xcassets                     # retire the static set
# project.yml: ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon -> HighRise
# Info.plist:  CFBundleIconName            AppIcon -> HighRise
xcodegen generate
```

`actool` then produces the layered glass asset + the `.icns` fallback. The CI
`Select Xcode 26+` step already prefers the newest Xcode 26–29 on the runner, so
it'll use a 27 automatically when one is available.

Sources: <https://useyourloaf.com/blog/adding-icon-composer-icons-to-xcode/>,
<https://developer.apple.com/documentation/Xcode/creating-your-app-icon-using-icon-composer>
