#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
out_path="$repo_root/build/apple-native"
apple_sdk="${DAEMON_APPLE_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
if [ ! -d "$apple_sdk" ]; then apple_sdk="$(xcrun --show-sdk-path)"; fi
arch_name="$(uname -m)"
case "$arch_name" in arm64|x86_64) ;; *) printf 'Unsupported Mac architecture: %s\n' "$arch_name" >&2; exit 1 ;; esac
mkdir -p "$out_path/objects" "$out_path/module-cache"
cd "$repo_root"

core_sources=(
  src/daemon/policy.cpp src/daemon/trace.cpp src/daemon/json.cpp src/daemon/bridge.cpp
  adapters/git_adapter.cpp adapters/posix_process.cpp
)
core_objects=()
for source_path in "${core_sources[@]}"; do
    object_path="$out_path/objects/$(basename "${source_path%.cpp}").o"
    xcrun clang++ -std=c++20 -O2 -Wall -Wextra -Wpedantic -isysroot "$apple_sdk" \
        -target "$arch_name-apple-macosx14.0" -I include -I adapters -c "$source_path" -o "$object_path"
    core_objects+=("$object_path")
done
xcrun ar rcs "$out_path/libDaemonNativeCore.a" "${core_objects[@]}"
swift_flags=(-swift-version 6 -sdk "$apple_sdk" -target "$arch_name-apple-macosx14.0" \
    -module-cache-path "$out_path/module-cache" -I apple/CoreHeaders -I "$out_path" -L "$out_path")
xcrun swiftc "${swift_flags[@]}" -O -parse-as-library -emit-library -static -emit-module \
    -module-name DaemonKit -emit-module-path "$out_path/DaemonKit.swiftmodule" \
    $(find apple/DaemonKit -name '*.swift' | sort) -o "$out_path/libDaemonKit.a"
xcrun swiftc "${swift_flags[@]}" -O -parse-as-library -emit-executable -module-name DaemonMac \
    apple/DaemonMac/DaemonMacApp.swift -lDaemonKit -lDaemonNativeCore -lc++ -o "$out_path/DaemonMac"
xcrun swiftc "${swift_flags[@]}" -O -parse-as-library -emit-executable -module-name DaemonBridgeChecks \
    apple/BridgeChecks/BridgeChecks.swift -lDaemonKit -lDaemonNativeCore -lc++ -o "$out_path/DaemonBridgeChecks"
xcrun swiftc "${swift_flags[@]}" -parse-as-library -typecheck apple/DaemonIOS/DaemonIOSDashboard.swift
"$out_path/DaemonBridgeChecks"
printf '%s\n' "$out_path/DaemonMac"
