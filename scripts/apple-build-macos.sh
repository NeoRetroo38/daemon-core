#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
scratch_path="$repo_root/build/apple-spm"
app_path="$repo_root/build/apple/Daemon.app"
apple_sdk="${DAEMON_APPLE_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
if [ ! -d "$apple_sdk" ]; then apple_sdk="$(xcrun --show-sdk-path)"; fi

cd "$repo_root"
case "${DAEMON_APPLE_BUILD_DRIVER:-direct}" in
    swiftpm)
        swift build --sdk "$apple_sdk" --configuration release --product DaemonMac --scratch-path "$scratch_path"
        bin_path="$(swift build --sdk "$apple_sdk" --configuration release --show-bin-path --scratch-path "$scratch_path")"
        ;;
    direct)
        DAEMON_APPLE_SDK="$apple_sdk" bash "$script_dir/apple-build-direct.sh"
        bin_path="$repo_root/build/apple-native"
        ;;
    *) printf '%s\n' 'DAEMON_APPLE_BUILD_DRIVER must be direct or swiftpm.' >&2; exit 1 ;;
esac
mkdir -p "$app_path/Contents/MacOS"
install -m 755 "$bin_path/DaemonMac" "$app_path/Contents/MacOS/Daemon"
install -m 644 "$repo_root/apple/DaemonMac/Info.plist" "$app_path/Contents/Info.plist"
plutil -lint "$app_path/Contents/Info.plist"
printf '%s\n' "$app_path"
