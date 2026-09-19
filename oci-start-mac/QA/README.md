# Native Web parity fixture

`WebParityFixture.swift` links the Debug app's production objects into a separate native executable. Every URLSession request is intercepted; unlisted endpoints fail locally. It uses an isolated preference domain and never launches the Java backend or connects to cloud resources.

`project.yml` is the source of the generated Xcode project, including the local `Vendor/SwiftTerm` package and the app target's package dependency. Keep dependency changes in this file and regenerate with XcodeGen before building; `build-dmg.sh` regenerates the project on every run.

Build the app, then run the fixture from a graphical macOS session:

```sh
xcodebuild -project oci-start-mac/OciStart.xcodeproj -scheme OciStart -configuration Debug -derivedDataPath /private/tmp/oci-mac-web-20260919-build-unrestricted CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES build
bash oci-start-mac/QA/run-web-parity.sh
```

The fixture checks local/remote login readiness gates, API token revision headers and explicit/unknown mutation receipts, guarded note HTML reads, the shared-region intersection, MFA server expiry, and migration receipt totals. It captures native light/dark and narrow windows with synthetic data, including the deployment selector, activated remote forms and the local-service waiting screen. Output defaults to `/private/tmp/oci-mac-web-qa`.

Additional checks run in the same isolated executable:

- `TableFixture.swift` scrolls the populated tenant table to its start, middle and end, checking that the same operation button stays visible, fixed and clickable, then restores the scroll position.
- `TerminalFixture.swift` exercises the bundled VT engine and native adapter: fragmented UTF-8/ANSI, cursor movement, alternate screen, resize preservation, queued output, reset, search, IME and disabled input.
- `ConsoleFixture.swift` executes the production canvas script in JavaScriptCore with local DOM/timer/RFB fakes. It checks connection acknowledgement, input gates, Unicode batches, cancellation, credentials and stale-session isolation. The dynamic engine import is replaced explicitly; no CDN or RFB connection is made.

This checks native rendering and request contracts. Real cloud actions, actual SSH/VNC sessions, and Java startup still require an appropriate integration environment.

Local verification on 2026-09-19: Xcode 13.2.1 / Swift 5.5.2, macOS 11, x86_64 Debug build passed with code signing disabled. The complete fixture exited 0: request contracts, 20 Console checks, 7 Terminal groups, fixed-column hit testing and header-height checks passed, and 30 native screenshots were captured. These results apply to the isolated fixtures and the integration limits above.

For packaging changes, regenerate the project first and also verify a universal Release archive. A Debug build of the existing project does not cover the regeneration step in `build-dmg.sh`. From the repository root, with XcodeGen on `PATH`:

```sh
xcodegen generate --spec oci-start-mac/project.yml --project oci-start-mac
xcodebuild archive -project oci-start-mac/OciStart.xcodeproj -scheme OciStart \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath /private/tmp/oci-mac-release-qa \
  -archivePath /private/tmp/oci-mac-release-qa/OciStart.xcarchive \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
```

Check both executable architectures and the `SwiftTerm_SwiftTerm.bundle` license resource inside the archive's app. This validates the native archive; the full DMG script additionally builds and bundles the Java backend and JREs.

Packaging verification on 2026-09-19: after regeneration with XcodeGen 2.45.4, Xcode 13.2.1 resolved the local SwiftTerm package and completed a fresh universal Release archive (exit 0). The archived app contains both `arm64` and `x86_64`, targets macOS 11.0, preserves version 5.7.92/build 10, includes the SwiftTerm license and Swift concurrency runtime, and passes `codesign --verify --deep --strict`. Repeated project generation produced identical project, Info.plist and entitlements files. The build log pipeline retained all 200,001 fixture lines while displaying 40 summary lines and preserving both success and failure exit codes. The complete Java/JRE/DMG assembly was not rerun for this dependency fix.
