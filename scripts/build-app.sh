#!/bin/bash
set -euo pipefail

version=${1:?usage: build-app.sh <version> [build-number]}
build_number=${2:-1}
root=$(cd "$(dirname "$0")/.." && pwd)
derived="$root/.build/xcode"
dist="$root/.build/dist"
app="$derived/Build/Products/Release/MotionWall.app"

xcodebuild \
  -project "$root/MotionWall.xcodeproj" \
  -scheme MotionWall \
  -configuration Release \
  -derivedDataPath "$derived" \
  -quiet \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  build

if [[ ! -f "$app/Contents/Frameworks/libMotionWallCore.dylib" ]]; then
  echo "libMotionWallCore.dylib is missing from $app/Contents/Frameworks" >&2
  exit 1
fi

set +e
"$app/Contents/Helpers/motionwall" --help >/dev/null 2>&1
status=$?
set -e
if (( status != 2 )); then
  echo "embedded motionwall --help exited with $status, expected the usage exit code 2" >&2
  exit 1
fi

mkdir -p "$dist"
rm -f "$dist/MotionWall-$version.zip"
ditto -c -k --keepParent "$app" "$dist/MotionWall-$version.zip"
echo "$dist/MotionWall-$version.zip"
