#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash build.sh
cd dist
ditto -c -k --sequesterRsrc --keepParent "XAssistant Mac.app" XAssistant-Mac-arm64.zip
shasum -a 256 XAssistant-Mac-arm64.zip > SHA256SUMS
printf 'Release files: dist/XAssistant-Mac-arm64.zip and dist/SHA256SUMS\n'
