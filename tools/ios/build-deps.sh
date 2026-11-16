#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
# SPDX-License-Identifier: BSD-3-Clause
#
# Build the dependencies of Itinerary for iOS (arm64 devices) as static libraries.
# Needs macOS with Xcode, Qt for iOS and the matching desktop Qt for the host tools,
# plus ninja, gettext, gperf, bison and flex.
#
# Usage: tools/ios/build-deps.sh <Qt for iOS dir> <install prefix>
#
# Packages that were already built with the same ref are skipped, so this can resume after
# a failure when the prefix is kept, e.g. by the CI cache.
set -euo pipefail

QT_IOS="$1"
PREFIX="$2"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${IOS_WORK_DIR:-$PWD/ios-work}"
QT_HOST_PATH="${QT_HOST_PATH:-$(dirname "$QT_IOS")/macos}"

mkdir -p "$PREFIX/logs" "$WORK"

while read -r name url ref args; do
    marker="$PREFIX/.built-$name-$ref"
    if [ -f "$marker" ]; then
        echo "== $name $ref: already built"
        continue
    fi
    echo "== $name $ref"
    src="$WORK/src/$name"
    build="$WORK/build/$name"
    log="$PREFIX/logs/$name.log"
    rm -rf "$src" "$build"
    git clone --quiet --depth 1 --branch "$ref" "$url" "$src"

    # shellcheck disable=SC2086 # extra arguments are meant to be split
    if ! {
        "$QT_IOS/bin/qt-cmake" -S "$src" -B "$build" -G Ninja \
            -DQT_HOST_PATH="$QT_HOST_PATH" \
            -DQT_ADDITIONAL_PACKAGES_PREFIX_PATH="$PREFIX" \
            -DCMAKE_PREFIX_PATH="$PREFIX" \
            -DCMAKE_INSTALL_PREFIX="$PREFIX" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DBUILD_SHARED_LIBS=OFF \
            -DBUILD_TESTING=OFF \
            -DBUILD_PYTHON_BINDINGS=OFF \
            -DBUILD_QCH=OFF \
            -DUSE_DBUS=OFF \
            $args \
        && cmake --build "$build" \
        && cmake --install "$build"
    } > "$log" 2>&1; then
        echo "!! $name failed, last lines of $log:"
        tail -n 60 "$log"
        exit 1
    fi
    touch "$marker"
done < <(grep -vE '^\s*(#|$)' "$HERE/deps.txt")
echo "All dependencies built."
