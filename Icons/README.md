# HighRise app icons

A one-command pipeline that turns your master artwork into app icons for
**macOS**, **iOS / iPadOS**, and **Windows**. It runs on a Mac and is the only
step that needs your artwork — the artwork itself is *not* committed here.

## 1. Generate

Your artwork lives at
`/Volumes/Satechi/HenSolutions/Apps/HighRise/HighRise iCons`. Point the script
at it (filenames are whatever yours are called):

```sh
./Icons/make-icons.sh \
  --macos "/Volumes/Satechi/HenSolutions/Apps/HighRise/HighRise iCons/<square-glass-icon>.png" \
  --ios   "/Volumes/Satechi/HenSolutions/Apps/HighRise/HighRise iCons/<full-bleed-square>.png"
```

`--ios`/`--win` are optional and fall back to the `--macos` master. For the
Windows `.ico` you need ImageMagick once: `brew install imagemagick`.

**Which artwork goes where** (this matters — wrong framing looks broken):

| Platform | Use | Why |
|---|---|---|
| **macOS** | the rounded-square **glass** icon, with its transparent margins | macOS draws it as-is; the squircle/glass look must be baked into the PNG |
| **iOS / iPadOS** | a **full-bleed, opaque square** (no rounding, no transparency) | the OS masks the corners — a pre-rounded icon gets double-rounded |
| **Windows** | full-bleed square (same as iOS) | shown square in taskbar/Explorer |

Masters should be **1024×1024** (or larger square).

## 2. What it produces

```
Icons/AppIcon-macOS.appiconset/   10 PNGs (16–512 @1x/@2x) + Contents.json
Icons/AppIcon-iOS.appiconset/     AppIcon-iOS-1024.png + Contents.json
Icons/windows/HighRise.ico        16/24/32/48/64/128/256 px
```

The two `.appiconset` folders are real Xcode asset catalogs — drop them straight
into a target.

## 3. Wiring macOS  (so the app running now gets its icon)

The generated set lives under `Icons/` so it never breaks CI before the PNGs
exist. Once generated, move it into the app and wire two settings:

```sh
mkdir -p HighRise/Assets.xcassets
cp -R Icons/AppIcon-macOS.appiconset HighRise/Assets.xcassets/AppIcon.appiconset
```

Add an `Assets.xcassets` catalog root if you don't have one:

```sh
cat > HighRise/Assets.xcassets/Contents.json <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON
```

Then in `project.yml`, under `targets: HighRise: settings: base:` add:

```yaml
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

and in `HighRise/Info.plist` add:

```xml
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
```

Finally `cd HighRise && xcodegen generate` and build. XcodeGen auto-includes the
`.xcassets` (it's under the `HighRise` sources path), so no other change is
needed.

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
