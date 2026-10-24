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

- `TableFixture.swift` checks the populated tenant table at its start, middle and end, including the fixed operation button's visibility and hit testing. It also checks horizontal gestures and Shift-wheel scrolling, single-line English headers, one-row filter/action bars, the final columns of narrow proxy/region tables, and independently scrolling rows in shared table fixtures at 640pt and 900pt.
- The login globe check samples the rendered native view across multiple frames, verifies actual rotation, pauses/resumes reduced motion and hidden windows, and captures timed screenshots. It uses main-run-loop callbacks to support the macOS 11 concurrency runtime. Header geometry and globe state probes are compiled only in Debug builds.
- `TerminalFixture.swift` exercises the bundled VT engine and native adapter: fragmented UTF-8/ANSI, cursor movement, alternate screen, resize preservation, queued output, reset, search, IME and disabled input.
- `ConsoleFixture.swift` executes the production canvas script in JavaScriptCore with local DOM/timer/RFB fakes. It checks connection acknowledgement, input gates, Unicode batches, cancellation, credentials and stale-session isolation. The dynamic engine import is replaced explicitly; no CDN or RFB connection is made.

This checks native rendering and request contracts. Real cloud actions, actual SSH/VNC sessions, and Java startup still require an appropriate integration environment.

For a focused layout/motion run after building, set `OCI_LAYOUT_QA_ONLY=1` when running the same script. This skips unrelated request/terminal/console suites and captures the narrow tenant, proxy and English-region pages, shared table stress cases, and the animated login globe. Failed assertions still produce a nonzero exit status.

On macOS 11, `NSEvent(cgEvent:)` produces a valid native scroll event with `window == nil`. Horizontal and Shift-wheel checks send these events through `NSApp.sendEvent` and the production monitor, with an isolated floating test window brought to the front; the original window level is restored afterward. The vertical check is explicitly split: `NSApp.sendEvent` must leave the horizontal viewport unchanged, then the same native event is delivered to the actual hit-tested row view and must advance its vertical scroll position without moving the horizontal viewport. This checks “vertical monitor ignores gesture + native row scroller handles vertical event”; it does not claim to exercise default `NSWindow` dispatch for a real window-associated event. Programmatic scroll changes only reset or restore positions and are never counted as successful wheel input.

Local verification on 2026-09-19: Xcode 13.2.1 / Swift 5.5.2, macOS 11, x86_64 Debug build passed with code signing disabled. The complete fixture exited 0: request contracts, 20 Console checks, 7 Terminal groups, fixed-column hit testing and header-height checks passed, and 30 native screenshots were captured. These results apply to the isolated fixtures and the integration limits above.

UI verification on 2026-09-20: the final production Debug build passed on Xcode 13.2.1 / Swift 5.5.2. Targeted native checks passed for the populated tenant/proxy/English-region tables (horizontal and Shift-wheel reachability, single-line headers, fixed tenant actions), the 640pt shared table/filter fixture, and the globe's actual rotation and pause/resume lifecycle. Separate light/dark captures confirmed both native row buttons and SwiftUI menu chrome; on macOS 11 the latter must draw outside `ButtonStyle`.

GUI validation was stopped at the user's request to keep the primary display free. The 900pt stress run exposed a fixture scroll-state reuse issue; the fixture now restores that state and passes the background Swift type-check, but its GUI rerun and the complete suite were not completed. Do not interpret these targeted results as a complete-suite pass. Future automated checks in this workspace should stay in the background; do not launch or raise these interactive fixture windows on the user's primary display.

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


## Headless AI chat regression

`AiChatFixture.swift` exercises the production AI chat view model with in-memory tenant/model services and WebSocket events. It links the Debug production objects without the app entry point, uses volatile process preferences, and rejects unexpected HTTP requests. It creates no application windows and makes no real AI/model calls.

After the background Debug build above, run:

```sh
bash oci-start-mac/QA/run-ai-chat.sh /private/tmp/oci-mac-web-20260919-build-unrestricted
```

The optional second argument selects the fixture output directory (default `/private/tmp/oci-mac-ai-chat-qa`). Rebuild before running after production changes, because the runner links existing objects.

Coverage includes delayed connection/initialization, strict initialization acknowledgements, normal streaming completion, duplicate sends, partial-response failures, empty successful replies, initialization and reply deadlines, keep-alives versus reply progress, silent connections, cancellation/teardown, replaced connections, stale tenant/model results, cancellation before a queued load starts, and switching tenants during a failed list refresh. Reply and heartbeat timers use shorter injected intervals; production defaults remain 30 seconds for initialization, 300 seconds without reply progress, 30-second heartbeats and 90 seconds without any incoming packet.

These checks validate client behavior with controlled responses. They do not validate a deployed backend, OCI authentication, proxy connectivity or actual model inference.

AI client verification on 2026-09-20: the final Xcode 13.2.1 / Swift 5.5.2 x86_64 Debug build passed. All 23 headless AI chat checks passed (exit 0), including the two tenant/cancellation race regressions. No application windows or real HTTP/model requests were used. Build log: `/private/tmp/oci-mac-ai-20260920-build.log`; fixture log: `/private/tmp/oci-mac-ai-chat-qa.log`.

A separate background CLI compiled the actual `NativeWSClient` with minimal API stubs for a localhost transport check. Its server started, but timed out without a connection while client execution approval was pending; the client approval call was interrupted. The real-socket handshake, clean-close/replacement cases and pre-open send queuing therefore remain unverified. This attempted check is not part of the 23 passing view-model checks. No GUI was launched.
