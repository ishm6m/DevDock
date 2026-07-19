# Contributing to DevDock

Thanks for your interest — contributions are welcome under the [MIT License](LICENSE).

## Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 16+ (Swift 5 language mode)
- [XcodeGen](https://github.com/yonsson/XcodeGen): `brew install xcodegen`

## Build & test

The Xcode project is **generated** from `project.yml` and is git-ignored, so always run
`xcodegen generate` after cloning or pulling.

```bash
xcodegen generate
# Run in Xcode with ⌘R, or from the command line:
xcodebuild -project DevDock.xcodeproj -scheme DevDock -destination 'platform=macOS' build
xcodebuild -project DevDock.xcodeproj -scheme DevDock -destination 'platform=macOS' test
```

The first build resolves the [Sparkle](https://github.com/sparkle-project/Sparkle) package
over the network (pinned in `project.yml`); it's cached afterward.

## Making a change

1. Branch off `main`.
2. Make the change and add tests where it makes sense. DevDock favors **pure, unit-testable
   functions** — e.g. framework classification, `lsof` parsing, and the auto-stop policy are
   plain functions with no process access, and are tested directly.
3. Run the test suite (above) — CI runs the same command on every PR.
4. Open a PR using the template.

## Guidelines

- **Kill safety is non-negotiable.** Every process-termination path must route through
  `Proc.isSafeToSignal` and `KillStrategy` — never call `kill()` directly. See the "Kill
  safety" section in the README.
- **Preferences migration:** any new field in `Preferences` must decode with
  `decodeIfPresent(...) ?? default` and be listed in `CodingKeys`, or existing users' settings
  silently reset.
- **No new dependency** for what the standard library or platform already provides.
- Match the surrounding style; keep diffs focused.

## Good first contributions

- Additional framework signatures in `FrameworkClassifier`.
- Real logo assets to replace the monogram badges.
- Richer tunnel URL resolution.

## Reporting bugs / requesting features

Use the [issue templates](https://github.com/ishm6m/DevDock/issues/new/choose). For bugs,
include your macOS version, DevDock version, and clear reproduction steps.
