# Native Web parity fixture

`WebParityFixture.swift` links the Debug app's production objects into a separate native executable. Every URLSession request is intercepted; unlisted endpoints fail locally. It uses an isolated preference domain and never launches the Java backend or connects to cloud resources.

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
