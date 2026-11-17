#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
# SPDX-License-Identifier: BSD-3-Clause
#
# Start the app in the iOS Simulator and check that it is still running after a while.
# Collects the app's console output, the system log of the app, a screenshot and crash reports.
# Needs an app bundle built with IOS_PLATFORM=simulator.
#
# Usage: tools/ios/simulator-smoke-test.sh <app bundle> <output dir> [seconds to wait]
set -euo pipefail

APP="$1"
OUT="$2"
WAIT="${3:-30}"
mkdir -p "$OUT"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"
executable="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP/Info.plist")"

# the newest iPhone of the newest iOS runtime installed
device="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
runtimes = json.load(sys.stdin)["devices"]
for runtime in sorted((r for r in runtimes if "iOS" in r), key=lambda r: [int(v) for v in r.rsplit("iOS-", 1)[1].split("-")], reverse=True):
    phones = [d for d in runtimes[runtime] if d["name"].startswith("iPhone")]
    if phones:
        print(phones[-1]["udid"], runtime, phones[-1]["name"])
        break
')"
read -r udid runtime name <<< "$device"
echo "== using $name ($runtime, $udid)"

xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b

# the simulator doesn't require signatures for x86_64 apps, but an ad-hoc one doesn't hurt
codesign --force --sign - --timestamp=none "$APP"
xcrun simctl install "$udid" "$APP"

# the unified log has messages of the system frameworks (and Qt's, if it doesn't write to stderr)
xcrun simctl spawn "$udid" log stream --level debug --style compact \
    --predicate "process == \"$executable\"" > "$OUT/system.log" 2>&1 &
log_pid=$!

echo "== launching $bundle_id"
# Qt only logs to stderr when told so if it isn't attached to a terminal, SIMCTL_CHILD_ variables are passed on
SIMCTL_CHILD_QT_FORCE_STDERR_LOGGING=1 \
SIMCTL_CHILD_QT_MESSAGE_PATTERN='%{time process} %{type} %{category}: %{message}' \
    xcrun simctl launch --console-pty --terminate-running-process "$udid" "$bundle_id" > "$OUT/console.log" 2>&1 &
launch_pid=$!

sleep "$WAIT"

running=1
if ! kill -0 "$launch_pid" 2> /dev/null; then
    running=0
fi
if ! xcrun simctl spawn "$udid" launchctl list | grep -q "UIKitApplication:$bundle_id"; then
    running=0
fi

xcrun simctl io "$udid" screenshot "$OUT/screenshot.png" || true

kill "$launch_pid" "$log_pid" 2> /dev/null || true
# crash reports of the simulated app end up on the host
find "$HOME/Library/Logs/DiagnosticReports" -name "$executable*" -newer "$APP/Info.plist" -exec cp {} "$OUT/" \; 2> /dev/null || true

echo "== console output (last 200 lines)"
tail -n 200 "$OUT/console.log"

if [ "$running" = 0 ]; then
    echo "!! the app is not running anymore after $WAIT seconds"
    exit 1
fi
echo "== the app is still running after $WAIT seconds"
