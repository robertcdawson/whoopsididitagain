#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

cd "$repository_root/backend"
npm run lint
npm run typecheck
npm run test:ci
npm run build

cd "$repository_root"
xcrun swift-format lint --recursive ios/WhoopsApp
xcodebuild \
  -project ios/WhoopsApp/WhoopsApp.xcodeproj \
  -scheme WhoopsApp \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/whoops-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
