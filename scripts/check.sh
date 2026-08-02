#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
derived_data="${DERIVED_DATA_PATH:-$repo_root/.build/xcode-derived-data}"

cd "$repo_root"

echo "==> Running Swift package tests"
swift test

echo "==> Building the macOS app"
xcodebuild \
  -project ProcessReporter.xcodeproj \
  -scheme ProcessReporter \
  -configuration Debug \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> All checks passed"
