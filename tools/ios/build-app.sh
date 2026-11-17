#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
# SPDX-License-Identifier: BSD-3-Clause
#
# Build the Itinerary app for iOS (arm64 devices), against the dependencies built by build-deps.sh.
# The result is an unsigned app bundle, signing happens in Xcode by the publishing account.
#
# Usage: tools/ios/build-app.sh <Qt for iOS dir> <dependency prefix> [build dir]
#
# The bundle identifier and the name shown on the home screen can be overridden with
# ITINERARY_IOS_BUNDLE_IDENTIFIER and ITINERARY_IOS_DISPLAY_NAME.
set -euo pipefail

QT_IOS="$1"
PREFIX="$2"
BUILD="${3:-$PWD/ios-build}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${IOS_WORK_DIR:-$PWD/ios-work}"
QT_HOST_PATH="${QT_HOST_PATH:-$(dirname "$QT_IOS")/macos}"
HOST_PREFIX="$PREFIX/host"
# the Breeze icons used by the app are compiled into it, see kirigami_package_breeze_icons()
BREEZE_ICONS_REF="v6.31.0"

mkdir -p "$PREFIX/logs" "$WORK"

# only find iOS libraries with pkg-config, not the ones installed on the host (e.g. by Homebrew)
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
unset PKG_CONFIG_PATH

if [ ! -d "$WORK/breeze-icons" ]; then
    git clone --quiet --depth 1 --branch "$BREEZE_ICONS_REF" https://invent.kde.org/frameworks/breeze-icons.git "$WORK/breeze-icons.tmp"
    mv "$WORK/breeze-icons.tmp" "$WORK/breeze-icons"
fi

log="$PREFIX/logs/itinerary-configure.log"
echo "== configuring itinerary"
if ! "$QT_IOS/bin/qt-cmake" -S "$SRC" -B "$BUILD" -G Ninja \
        -DQT_HOST_PATH="$QT_HOST_PATH" \
        -DQT_ADDITIONAL_PACKAGES_PREFIX_PATH="$PREFIX" \
        -DCMAKE_PREFIX_PATH="$PREFIX" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_MAJOR_VERSION=6 \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTING=OFF \
        -DKF_IGNORE_PLATFORM_CHECK=ON \
        -DKF6_HOST_TOOLING="$HOST_PREFIX/lib/cmake" \
        -DBREEZEICONS_DIR="$WORK/breeze-icons" \
        -DITINERARY_IOS_BUNDLE_IDENTIFIER="${ITINERARY_IOS_BUNDLE_IDENTIFIER:-org.example.itinerary-fork}" \
        -DITINERARY_IOS_DISPLAY_NAME="${ITINERARY_IOS_DISPLAY_NAME:-Itinerary (unofficial)}" \
        > "$log" 2>&1; then
    echo "!! configuring failed, last lines of $log:"
    tail -n 80 "$log"
    exit 1
fi

log="$PREFIX/logs/itinerary-build.log"
echo "== building itinerary"
# keep going to see as many errors as possible per CI run
if ! cmake --build "$BUILD" -- -k 0 > "$log" 2>&1; then
    echo "!! building failed, errors in $log:"
    grep -E -A5 'error:|FAILED:|Undefined symbols|ld: ' "$log" | head -n 300
    exit 1
fi

app="$(find "$BUILD/bin" "$BUILD/src/app" -maxdepth 1 -name '*.app' -type d 2>/dev/null | head -n 1)"
if [ -z "$app" ]; then
    echo "!! no app bundle found"
    exit 1
fi
echo "Built $app"
