#!/bin/bash
set -euo pipefail

# Headless: links existing Debug production objects, then runs in-memory fake
# HTTP/service and WebSocket checks. Does not build the app or create any UI.
# Usage: QA/run-ai-chat.sh [Debug DerivedData directory] [fixture output directory]
qa_root="$(cd "$(dirname "$0")/.." && pwd)"
qa_derived="${1:-/private/tmp/oci-mac-web-20260919-build-unrestricted}"
qa_output="${2:-/private/tmp/oci-mac-ai-chat-qa}"
qa_arch="${OCI_QA_ARCH:-$(uname -m)}"
qa_products="$qa_derived/Build/Products/Debug"
qa_objects="$qa_derived/Build/Intermediates.noindex/OciStart.build/Debug/OciStart.build/Objects-normal/$qa_arch"
qa_terminal_objects="$qa_derived/Build/Intermediates.noindex/SwiftTerm.build/Debug/SwiftTerm.build/Objects-normal/$qa_arch"
if [[ ! -d "$qa_objects" || ! -d "$qa_terminal_objects" || ! -e "$qa_products/OciStart.swiftmodule" ]]; then
  echo "Missing Debug objects/module for $qa_arch. Build OciStart with Debug / CODE_SIGNING_ALLOWED=NO first, then pass its DerivedData directory." >&2
  exit 2
fi
mkdir -p "$qa_output"
rg --files "$qa_objects" -g '*.o' | rg -v '/main\.o$' | LC_ALL=C sort > "$qa_output/objects.txt"
rg --files "$qa_terminal_objects" -g '*.o' | LC_ALL=C sort >> "$qa_output/objects.txt"
xcrun swiftc -g -swift-version 5 -parse-as-library -enable-testing -target "$qa_arch-apple-macos11.0" \
  -module-cache-path "$qa_output/module-cache" -I "$qa_products" \
  -Xlinker -rpath -Xlinker "$qa_products/OciStart.app/Contents/Frameworks" \
  "$qa_root/QA/AiChatFixture.swift" @"$qa_output/objects.txt" \
  -o "$qa_output/AiChatFixture"
"$qa_output/AiChatFixture"
