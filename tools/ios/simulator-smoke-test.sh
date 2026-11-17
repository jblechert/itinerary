#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
# SPDX-License-Identifier: BSD-3-Clause
#
# Start the app in the iOS Simulator and check that it is still running after a while.
# Collects the app's console output, the system log of the app, screenshots and crash reports.
# Needs an app bundle built with IOS_PLATFORM=simulator.
#
# The app is started twice: freshly installed, showing the welcome page, and with the welcome page
# already dismissed and German as language, showing the main page.
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
xcrun simctl bootstatus "$udid" -b > /dev/null
# without a location, starting the app with the location permission granted takes about 20 seconds longer
xcrun simctl location "$udid" set 52.5251,13.3694 || true

# the simulator doesn't require signatures for x86_64 apps, but an ad-hoc one doesn't hurt
codesign --force --sign - --timestamp=none "$APP"

# the unified log has messages of the system frameworks (and Qt's, if it doesn't write to stderr)
xcrun simctl spawn "$udid" log stream --level info --style compact \
    --predicate "process == \"$executable\"" > "$OUT/system.log" 2>&1 &
log_pid=$!

install() {
    xcrun simctl uninstall "$udid" "$bundle_id" 2> /dev/null || true
    xcrun simctl install "$udid" "$APP"
    # the app asks for the location when starting, which would cover the screenshots
    xcrun simctl privacy "$udid" grant location "$bundle_id"
}

# the process ID of the running app, fails if it isn't running
app_pid() {
    local services
    services="$(xcrun simctl spawn "$udid" launchctl list)"
    awk -v label="UIKitApplication:$bundle_id" 'index($3, label) == 1 && $1 != "-" { print $1; found = 1 } END { exit !found }' <<< "$services"
}

failed=0
# launch the app, wait and take a screenshot; usage: run <name> [environment variables for the app...]
run() {
    local name="$1"
    shift
    echo "== launching $bundle_id ($name)"
    # Qt only logs to stderr when told so if it isn't attached to a terminal, SIMCTL_CHILD_ variables are passed on
    env SIMCTL_CHILD_QT_FORCE_STDERR_LOGGING=1 \
        SIMCTL_CHILD_QT_MESSAGE_PATTERN='%{time process} %{type} %{category}: %{message}' \
        "$@" \
        xcrun simctl launch --console-pty --terminate-running-process "$udid" "$bundle_id" > "$OUT/console-$name.log" 2>&1 &
    local launch_pid=$!
    sleep "$WAIT"
    local running=1 pid
    pid="$(app_pid)" || running=0
    xcrun simctl io "$udid" screenshot "$OUT/screenshot-$name.png" > /dev/null 2>&1 || true
    # simulated apps are processes of the host, so their stacks can be sampled, e.g. to see where they hang
    if [ "$running" = 1 ]; then
        sample "$pid" 3 -file "$OUT/sample-$name.txt" > /dev/null 2>&1 || true
    fi
    xcrun simctl terminate "$udid" "$bundle_id" 2> /dev/null || true
    kill "$launch_pid" 2> /dev/null || true
    wait "$launch_pid" 2> /dev/null || true

    echo "== console output ($name, last 100 lines)"
    tail -n 100 "$OUT/console-$name.log"
    if [ "$running" = 0 ]; then
        echo "!! the app is not running anymore after $WAIT seconds ($name)"
        failed=1
    fi
}

install
run welcome

# freshly installed again, with the welcome page marked as shown in the app's settings (QSettings uses
# the user defaults on iOS), so the main page is shown
install
container="$(xcrun simctl get_app_container "$udid" "$bundle_id" data)"
mkdir -p "$container/Library/Preferences"
# written in the simulator, so its preferences daemon knows about it
xcrun simctl spawn "$udid" defaults write "$container/Library/Preferences/org.kde.itinerary" Settings.WelcomePageShown -bool true
# KI18n follows LANGUAGE, to check that the bundled translations are found
run main-de SIMCTL_CHILD_LANGUAGE=de

kill "$log_pid" 2> /dev/null || true
# crash reports of the simulated app end up on the host
find "$HOME/Library/Logs/DiagnosticReports" -name "$executable*" -newer "$APP/Info.plist" -exec cp {} "$OUT/" \; 2> /dev/null || true

if [ "$failed" = 1 ]; then
    exit 1
fi
echo "== the app is still running after $WAIT seconds"
