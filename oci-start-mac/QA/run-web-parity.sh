#!/bin/bash
set -euo pipefail

# Build the app first with Debug / CODE_SIGNING_ALLOWED=NO. This harness links
# its production objects into a separate executable, with all HTTP intercepted.
# OCI_LAYOUT_QA_ONLY=1 skips shared table stress and API contract checks, keeping
# populated narrow tenants/proxy/English-regions pages and login globe motion.
# It still sends native wheel events, captures final columns/timed globe frames,
# and exits nonzero on failed geometry or lifecycle assertions.
qa_root="$(cd "$(dirname "$0")/.." && pwd)"
qa_derived="${1:-/private/tmp/oci-mac-web-20260919-build-unrestricted}"
qa_output="${2:-/private/tmp/oci-mac-web-qa}"
qa_arch="$(uname -m)"
qa_products="$qa_derived/Build/Products/Debug"
qa_objects="$qa_derived/Build/Intermediates.noindex/OciStart.build/Debug/OciStart.build/Objects-normal/$qa_arch"
qa_terminal_objects="$qa_derived/Build/Intermediates.noindex/SwiftTerm.build/Debug/SwiftTerm.build/Objects-normal/$qa_arch"
mkdir -p "$qa_output"
if command -v rg >/dev/null 2>&1; then
  rg --files "$qa_objects" -g '*.o' | rg -v '/main\.o$' > "$qa_output/objects.txt"
  rg --files "$qa_terminal_objects" -g '*.o' >> "$qa_output/objects.txt"
else
  find "$qa_objects" -name '*.o' ! -name 'main.o' > "$qa_output/objects.txt"
  if [ -d "$qa_terminal_objects" ]; then
    find "$qa_terminal_objects" -name '*.o' >> "$qa_output/objects.txt"
  fi
fi
cp "$qa_root/QA/WebParityFixture.swift" "$qa_output/main.swift"
xcrun swiftc -g -enable-testing -target "$qa_arch-apple-macos11.0" \
  -module-cache-path "$qa_output/module-cache" -I "$qa_products" \
  -Xlinker -rpath -Xlinker "$qa_products/OciStart.app/Contents/Frameworks" \
  "$qa_output/main.swift" "$qa_root/QA/TerminalFixture.swift" \
  "$qa_root/QA/ConsoleFixture.swift" "$qa_root/QA/TableFixture.swift" @"$qa_output/objects.txt" \
  -o "$qa_output/WebParityFixture"
OCI_CAPTURE_DIR="$qa_output/shots" "$qa_output/WebParityFixture"
