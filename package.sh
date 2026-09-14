#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "${SIGNING_IDENTITY:--}" == "-" && "${ALLOW_ADHOC_PACKAGE:-0}" != 1 ]]; then
    echo 'Release packaging requires SIGNING_IDENTITY (Developer ID Application). Ad-hoc signatures lose privacy grants across updates.' >&2
    echo 'For local testing only, set ALLOW_ADHOC_PACKAGE=1. Do not publish that build as a stable update.' >&2
    exit 1
fi
bash build.sh
if [[ "${ALLOW_ADHOC_PACKAGE:-0}" != 1 ]]; then
    codesign -dv "dist/XAssistant Mac.app" 2>&1 | /usr/bin/grep -q '^Authority=Developer ID Application:' || {
        echo 'Release signing must use a Developer ID Application certificate.' >&2
        exit 1
    }
fi
"dist/XAssistant Mac.app/Contents/MacOS/XAssistantMac" --media-self-test
cd dist
ditto -c -k --sequesterRsrc --keepParent "XAssistant Mac.app" XAssistant-Mac-arm64.zip
shasum -a 256 XAssistant-Mac-arm64.zip > SHA256SUMS
printf 'Release files: dist/XAssistant-Mac-arm64.zip and dist/SHA256SUMS\n'
