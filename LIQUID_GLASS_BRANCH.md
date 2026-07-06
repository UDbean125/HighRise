# Liquid Glass branch (local Xcode 27 builds)

This branch wires the dynamic Liquid Glass **`HighRise/HighRise.icon`** as the
app icon, replacing the static `AppIcon.appiconset` on `main` /
`claude/magical-mendel-11m60a`.

**Use it for local builds on Xcode 27:**

```sh
git checkout claude/liquid-glass-icon
xcodegen generate
open HighRise.xcodeproj      # build/run — the app gets the Liquid Glass icon
```

**Heads-up — CI on this branch is expected to be RED.** GitHub's hosted runners
currently have Xcode 26.3, whose `actool` crashes compiling a 27-authored
`.icon`. This branch is intentionally *not* for merging yet; it's a convenience
for building the glass icon locally on Xcode 27. The shipping branch keeps the
static icon and stays green.

When GitHub runners ship Xcode 27 GA (~fall 2026), this becomes mergeable as-is
and the static `AppIcon.appiconset` can be retired everywhere.
