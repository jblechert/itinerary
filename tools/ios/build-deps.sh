#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
# SPDX-License-Identifier: BSD-3-Clause
#
# Build the dependencies of Itinerary for iOS as static libraries, for arm64 devices or, with
# IOS_PLATFORM=simulator, for the simulator (see platform.sh). Use separate prefixes for both.
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
# shellcheck source=platform.sh
. "$HERE/platform.sh"
WORK="${IOS_WORK_DIR:-$PWD/ios-work}"
QT_HOST_PATH="${QT_HOST_PATH:-$(dirname "$QT_IOS")/macos}"
# build tools that run during the build (e.g. kconfig_compiler) are built for macOS, see host-deps.txt
HOST_PREFIX="$PREFIX/host"

mkdir -p "$PREFIX/logs" "$WORK"

# only find iOS libraries with pkg-config, not the ones installed on the host (e.g. by Homebrew)
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
unset PKG_CONFIG_PATH

# clone the package and apply our patches; usage: fetch <name> <url> <ref> <source dir>
# a hash of the patches applied to a dependency, so changed patches cause a rebuild
patches_hash() {
    local dir="$HERE/patches/$1"
    if [ -d "$dir" ]; then
        printf -- "-%s" "$(cat "$dir"/*.patch | shasum | cut -c1-12)"
    fi
}

# a hash of the extra CMake arguments of a dependency, so changing them causes a rebuild
args_hash() {
    if [ -n "$1" ]; then
        printf -- "-%s" "$(printf '%s' "$1" | shasum | cut -c1-8)"
    fi
}

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

# The translations of KDE packages are not in their git repositories, only in the release tarballs.
# Prints the tarball URL of a package, or nothing for packages not released on download.kde.org.
release_tarball() {
    local name="$1" url="$2" version="${3#v}"
    case "$url" in
        https://invent.kde.org/frameworks/*)
            echo "https://download.kde.org/stable/frameworks/${version%.*}/$name-$version.tar.xz" ;;
        https://invent.kde.org/plasma/*)
            echo "https://download.kde.org/stable/plasma/$version/$name-$version.tar.xz" ;;
        https://invent.kde.org/*)
            # KDE Gear versions are year.month.patch, everything else is released on its own
            if [[ "$version" =~ ^[0-9]{2}\.[0-9]{2}\.[0-9]+$ ]]; then
                echo "https://download.kde.org/stable/release-service/$version/src/$name-$version.tar.xz"
            else
                echo "https://download.kde.org/stable/$name/$name-$version.tar.xz"
            fi ;;
    esac
}

# Installs the compiled translations of a package to $PREFIX/share/locale: gettext catalogs (po/) as .mo
# and Qt translations (poqm/) as .qm. Missing translations are not an error, they only show up as English text.
install_translations() {
    local name="$1" url="$2" ref="$3"
    local marker="$PREFIX/.translations-$name-$ref"
    [ -f "$marker" ] && return
    local tarball
    tarball="$(release_tarball "$name" "$url" "$ref")"
    [ -n "$tarball" ] || return 0
    echo "== translations of $name $ref"
    local dir="$WORK/translations/$name"
    rm -rf "$dir"
    mkdir -p "$dir"
    if ! curl -fsSL --retry 3 "$tarball" | tar -xJf - -C "$dir" --strip-components 1; then
        echo "   no translations for $name: downloading $tarball failed"
        return 0
    fi
    local lconvert="$QT_HOST_PATH/bin/lconvert" po lang dest count=0
    for po in "$dir"/po/*/*.po "$dir"/poqm/*/*.po; do
        [ -f "$po" ] || continue
        lang="$(basename "$(dirname "$po")")"
        dest="$PREFIX/share/locale/$lang/LC_MESSAGES"
        mkdir -p "$dest"
        case "$po" in
            "$dir"/po/*) msgfmt -o "$dest/$(basename "$po" .po).mo" "$po" ;;
            *) "$lconvert" -i "$po" -o "$dest/$(basename "$po" .po).qm" ;;
        esac || { echo "   compiling $po failed"; continue; }
        count=$((count + 1))
    done
    echo "   installed $count translation catalogs"
    rm -rf "$dir"
    touch "$marker"
}

# host tools, built natively for macOS with the desktop Qt
while read -r name url ref args; do
    marker="$HOST_PREFIX/.built-$name-$ref$(patches_hash "$name")$(args_hash "$args")"
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
            -DQT_MAJOR_VERSION=6 \
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
    install_translations "$name" "$url" "$ref"
    marker="$PREFIX/.built-$name-$ref$(patches_hash "$name")$(args_hash "$args")"
    if [ -f "$marker" ]; then
        echo "== $name $ref: already built"
        continue
    fi
    echo "== $name $ref"
    src="$WORK/src/$name"
    build="$WORK/build/$name"
    log="$PREFIX/logs/$name.log"
    # deps.txt can refer to the installation prefix
    args="${args//\$PREFIX/$PREFIX}"
    rm -rf "$build"
    fetch "$name" "$url" "$ref" "$src"

    # iso-codes is architecture independent data, built with autotools
    if [ "$name" = iso-codes ]; then
        if ! {
            cd "$src" \
            && ./configure --prefix="$PREFIX" $args \
            && make -j"$(sysctl -n hw.ncpu)" install \
            && cd - > /dev/null
        } > "$log" 2>&1; then
            echo "!! $name failed, last lines of $log:"
            tail -n 60 "$log"
            exit 1
        fi
        touch "$marker"
        continue
    fi

    # OpenSSL has its own build system
    if [ "$name" = openssl ]; then
        if ! {
            cd "$src" \
            && ./Configure "$IOS_OPENSSL_TARGET" "$IOS_VERSION_MIN_FLAG=$IOS_DEPLOYMENT_TARGET" no-shared no-tests no-apps no-docs no-module \
                --prefix="$PREFIX" --openssldir="$PREFIX/ssl" $args \
            && make -j"$(sysctl -n hw.ncpu)" build_libs \
            && make install_dev \
            && cd - > /dev/null
        } > "$log" 2>&1; then
            echo "!! $name failed, last lines of $log:"
            tail -n 60 "$log"
            exit 1
        fi
        touch "$marker"
        continue
    fi

    # shellcheck disable=SC2086 # extra arguments are meant to be split
    if ! {
        "$QT_IOS/bin/qt-cmake" -S "$src" -B "$build" -G Ninja \
            -DQT_HOST_PATH="$QT_HOST_PATH" \
            -DQT_ADDITIONAL_PACKAGES_PREFIX_PATH="$PREFIX" \
            -DCMAKE_PREFIX_PATH="$PREFIX" \
            -DCMAKE_INSTALL_PREFIX="$PREFIX" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
            -DQT_MAJOR_VERSION=6 \
            -DCMAKE_OSX_SYSROOT="$IOS_SYSROOT" \
            -DCMAKE_OSX_ARCHITECTURES="$IOS_ARCH" \
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
