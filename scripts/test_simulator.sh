#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate_project.py
mkdir -p build/artifacts
xcrun simctl list devices available -j > build/devices.json
device=$(python3 - <<'PY'
import json
d=json.load(open('build/devices.json'))
phones=[x for runtime,items in d['devices'].items() if '.iOS-' in runtime for x in items if x['isAvailable'] and x['name'].startswith('iPhone')]
phones.sort(key=lambda x: ('Pro Max' not in x['name'], x['name']), reverse=False)
if not phones: raise SystemExit('No iPhone simulator runtime is installed')
print(phones[0]['udid'])
PY
)
xcrun simctl boot "$device" || true
python3 - "$device" <<'PY'
import subprocess,sys
subprocess.run(['xcrun','simctl','bootstatus',sys.argv[1],'-b'],check=True,timeout=180)
PY
xcodebuild -project AikinRecorder.xcodeproj -scheme AikinRecorder \
  -configuration Debug -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath build/simulator -parallel-testing-enabled NO \
  -resultBundlePath build/artifacts/Tests.xcresult CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES ARCHS="$(uname -m)" SWIFT_COMPILATION_MODE=wholemodule test \
  2>&1 | tee build/artifacts/simulator-test.log
xcrun simctl install "$device" build/simulator/Build/Products/Debug-iphonesimulator/AikinRecorder.app
xcrun simctl status_bar "$device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl launch "$device" app.aikin.recorder
sleep 3
xcrun simctl io "$device" screenshot build/artifacts/iPhone-library.png

