#!/bin/bash
set -euo pipefail
# Download the latest published Apple Silicon build; no developer tools or sudo needed.
repo="nope-gao/XAssistant-Mac"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    echo 'Requires an Apple Silicon Mac. / 需要 Apple Silicon Mac。' >&2
    exit 1
fi
major="$(sw_vers -productVersion | cut -d. -f1)"
if (( major < 13 )); then
    echo 'Requires macOS 13 or newer. / 需要 macOS 13 或更新版本。' >&2
    exit 1
fi
if pgrep -x XAssistantMac >/dev/null; then
    echo 'Quit XAssistant Mac before installing, then run this command again. / 请先退出 XAssistant Mac，再重新运行。' >&2
    exit 1
fi
work="$(mktemp -d)"
stage=""
app="$HOME/Applications/XAssistant Mac.app"
cleanup() {
    if [[ -n "$stage" && -d "$stage/previous.app" && ! -e "$app" ]]; then
        mv "$stage/previous.app" "$app"
    fi
    rm -rf "$work"
    if [[ -n "$stage" ]]; then rm -rf "$stage"; fi
}
trap cleanup EXIT
curl --fail --silent --show-error --location --retry 3 "https://api.github.com/repos/$repo/releases/latest" -o "$work/release.json" || {
    echo 'No downloadable release is available, or GitHub could not be reached. / 暂无可下载版本，或无法连接 GitHub。' >&2
    exit 1
}
version="$(plutil -extract tag_name raw -o - "$work/release.json")"
if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo 'Unexpected release version.' >&2; exit 1
fi
url="https://github.com/$repo/releases/download/$version"
for file in XAssistant-Mac-arm64.zip SHA256SUMS; do
    curl --fail --silent --show-error --location --retry 3 "$url/$file" -o "$work/$file"
done
(cd "$work" && shasum -a 256 -c SHA256SUMS)
ditto -x -k "$work/XAssistant-Mac-arm64.zip" "$work/unpacked"
sourceApp="$work/unpacked/XAssistant Mac.app"
codesign --verify --deep --strict "$sourceApp"
bundleID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$sourceApp/Contents/Info.plist")"
[[ "$bundleID" == local.jasongao.xassistantmac ]] || { echo 'Unexpected app bundle.' >&2; exit 1; }
# TCC grants are bound to a code requirement, not just the bundle ID or filename.
# Test the downloaded app against the installed app's requirement before replacing anything.
if [[ -d "$app" ]]; then
    current_requirement="$(codesign -d -r- "$app" 2>&1 | sed -n -E 's/^#? ?designated => //p')"
    if [[ -z "$current_requirement" ]] || ! codesign --verify --strict --test-requirement "=$current_requirement" "$sourceApp" 2>/dev/null; then
        echo 'Update stopped: the new signing identity would invalidate Input Monitoring. Your installed app and recordings are unchanged.' >&2
        echo '已停止更新：新版签名不兼容现有输入监控授权，当前应用和记录均未改动。' >&2
        echo 'Use a release signed with the same Developer ID. Changing signing identity requires authorizing the new app once in System Settings.' >&2
        exit 1
    fi
fi
mkdir -p "$HOME/Applications"
stage="$(mktemp -d "$HOME/Applications/.xassistant-install.XXXXXX")"
ditto "$sourceApp" "$stage/new.app"
if [[ -e "$app" ]]; then mv "$app" "$stage/previous.app"; fi
mv "$stage/new.app" "$app"
printf 'Installed %s: %s\n' "$version" "$app"
echo 'Open the app and enable Input Monitoring. / 打开应用并开启输入监控。'
echo 'If macOS blocks it, use System Settings → Privacy & Security → Open Anyway after reviewing the app.'
open "$app"
