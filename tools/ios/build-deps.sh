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
# Patches in tools/ios/patches/<package>/*.patch are applied before building that package.
set -euo pipefail

QT_IOS="$1"
PREFIX="$2"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${IOS_WORK_DIR:-$PWD/ios-work}"
QT_HOST_PATH="${QT_HOST_PATH:-$(dirname "$QT_IOS")/macos}"
# build tools that run during the build (e.g. kconfig_compiler) are built for macOS, see host-deps.txt
HOST_PREFIX="$PREFIX/host"

mkdir -p "$PREFIX/logs" "$WORK"

# clone the package and apply our patches; usage: fetch <name> <url> <ref> <source dir>
fetch() {
    rm -rf "$4"
    git clone --quiet --depth 1 --branch "$3" "$2" "$4"
    # fixes needed for iOS that aren't in the used release yet
    for patch in "$HERE/patches/$1"/*.patch; do
        [ -f "$patch" ] || continue
        echo "   applying $(basename "$patch")"
        git -C "$4" apply "$patch"
    done
}

# host tools, built natively for macOS with the desktop Qt
while read -r name url ref args; do
    marker="$HOST_PREFIX/.built-$name-$ref"
    if [ -f "$marker" ]; then
        echo "== host $name $ref: already built"
        continue
    fi
    echo "== host $name $ref"
    src="$WORK/host-src/$name"
    build="$WORK/host-build/$name"
    log="$PREFIX/logs/host-$name.log"
    rm -rf "$build"
    git clone --quiet --depth 1 --branch "$ref" "$url" "$src.tmp" && rm -rf "$src" && mv "$src.tmp" "$src"
    # shellcheck disable=SC2086 # extra arguments are meant to be split
    if ! {
        cmake -S "$src" -B "$build" -G Ninja \
            -DCMAKE_PREFIX_PATH="$QT_HOST_PATH;$HOST_PREFIX;$PREFIX" \
            -DCMAKE_INSTALL_PREFIX="$HOST_PREFIX" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
            -DBUILD_TESTING=OFF \
            -DBUILD_QCH=OFF \
            -DUSE_DBUS=OFF \
            $args \
        && cmake --build "$build" \
        && cmake --install "$build"
    } > "$log" 2>&1; then
        echo "!! host $name failed, last lines of $log:"
        tail -n 60 "$log"
        exit 1
    fi
    touch "$marker"
done < <(grep -vE '^\s*(#|$)' "$HERE/host-deps.txt")

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
    rm -rf "$build"
    fetch "$name" "$url" "$ref" "$src"

    # shellcheck disable=SC2086 # extra arguments are meant to be split
    if ! {
        "$QT_IOS/bin/qt-cmake" -S "$src" -B "$build" -G Ninja \
            -DQT_HOST_PATH="$QT_HOST_PATH" \
            -DQT_ADDITIONAL_PACKAGES_PREFIX_PATH="$PREFIX" \
            -DCMAKE_PREFIX_PATH="$PREFIX" \
            -DCMAKE_INSTALL_PREFIX="$PREFIX" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DBUILD_SHARED_LIBS=OFF \
            -DBUILD_TESTING=OFF \
            -DBUILD_PYTHON_BINDINGS=OFF \
            -DBUILD_QCH=OFF \
            -DUSE_DBUS=OFF \
            -DKF_IGNORE_PLATFORM_CHECK=ON \
            -DKF6_HOST_TOOLING="$HOST_PREFIX/lib/cmake" \
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
