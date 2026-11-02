#!/bin/bash
# Generates BiathlonKit's Java bindings with swift-java's jextract (JNI mode):
# the Swift thunks into Sources/BiathlonKit/Generated, compiled with BiathlonKit,
# and the Java sources into the directory given as the first argument.
set -euo pipefail

package="$(cd "$(dirname "$0")/.." && pwd)"
java_output="$1"

rm -rf "$package/Sources/BiathlonKit/Generated" "$java_output"
swift run --package-path "$package" swift-java jextract \
  --config "$package/swift-java.config" \
  --swift-module BiathlonKit \
  --input-swift "$(cd "$package/Sources/BiathlonKit/Shared" && pwd -P)" \
  --output-swift "$package/Sources/BiathlonKit/Generated" \
  --output-java "$java_output"
