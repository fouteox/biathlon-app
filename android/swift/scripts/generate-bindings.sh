#!/bin/bash
# Generates the Java bindings to BiathlonKit, its shared sources and the Android-only ones in
# Sources/BiathlonKit/Android, with swift-java's jextract (JNI mode): the Swift thunks into
# Sources/BiathlonKit/Generated, compiled with BiathlonKit, and the Java sources into the
# directory given as the first argument.
#
# Usage: generate-bindings.sh <java-output-directory> <debug|release>
# A debug build also binds what BiathlonKit compiles in DEBUG only (IBUClient.sample).
set -euo pipefail

package="$(cd "$(dirname "$0")/.." && pwd)"
java_output="$1"
configuration="$2"

# jextract resolves #if blocks with the compiler's own build configuration for Android.
frontend_flags=(-print-static-build-config -target aarch64-unknown-linux-android28 -swift-version 6)
case "$configuration" in
  debug) frontend_flags+=(-D DEBUG) ;;
  release) ;;
  *) echo "unknown configuration: $configuration" >&2; exit 1 ;;
esac
build_config="$package/.build/jextract-$configuration.json"
mkdir -p "$package/.build"
swift frontend "${frontend_flags[@]}" > "$build_config"

rm -rf "$package/Sources/BiathlonKit/Generated" "$java_output"
swift run --package-path "$package" swift-java jextract \
  --config "$package/swift-java.config" \
  --static-build-config "$build_config" \
  --swift-module BiathlonKit \
  --input-swift "$(cd "$package/Sources/BiathlonKit/Shared" && pwd -P),$package/Sources/BiathlonKit/Android" \
  --output-swift "$package/Sources/BiathlonKit/Generated" \
  --output-java "$java_output"
