#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate_project.py
mkdir -p build/artifacts
xcodebuild -version | tee build/artifacts/xcode-version.txt
set +e
xcodebuild -project AikinRecorder.xcodeproj -scheme AikinRecorder \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' build 2>&1 | tee build/artifacts/device-build.log
status=${PIPESTATUS[0]}
set -e
if [ "$status" -ne 0 ]; then
  grep -E "error:|fatal error:|BUILD FAILED" build/artifacts/device-build.log | head -40 | while IFS= read -r line; do
    echo "::error::$line"
  done
  exit "$status"
fi
app=build/device/Build/Products/Release-iphoneos/AikinRecorder.app
test -x "$app/AikinRecorder"
xcrun lipo "$app/AikinRecorder" -verify_arch arm64
if codesign -dv "$app" >/dev/null 2>&1; then
  echo 'Expected an unsigned app, but found a code signature.' >&2
  exit 1
fi
mkdir -p build/package/Payload
ditto "$app" build/package/Payload/AikinRecorder.app
(cd build/package && ditto -c -k --keepParent Payload ../artifacts/AikinRecorder-1.6.0-unsigned.ipa)
shasum -a 256 build/artifacts/AikinRecorder-1.6.0-unsigned.ipa > build/artifacts/SHA256SUMS.txt
echo 'Unsigned IPA created. It must be signed with your certificate and provisioning profile before installation.'

