<!-- Thanks for contributing to DevDock! -->

## Summary

<!-- What does this change and why? -->

## Testing

<!-- How did you verify it? -->

- [ ] `xcodegen generate`
- [ ] `xcodebuild -project DevDock.xcodeproj -scheme DevDock -destination 'platform=macOS' test` passes
- [ ] Added/updated tests where it made sense

## Checklist

- [ ] No new dependency added for something the stdlib/platform already ships
- [ ] Any process-termination change still routes through `Proc.isSafeToSignal` / `KillStrategy`
- [ ] New `Preferences` fields decode with `decodeIfPresent` (existing settings must not reset)
