# SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
# SPDX-License-Identifier: BSD-3-Clause
#
# The iOS platform to build for, sourced by build-deps.sh and build-app.sh.
# IOS_PLATFORM is "device" (the default, arm64) or "simulator". The simulator architecture is x86_64,
# as the simulator slices of the Qt for iOS binary packages are x86_64 only; it runs on Apple Silicon too.

IOS_PLATFORM="${IOS_PLATFORM:-device}"
case "$IOS_PLATFORM" in
    device)
        IOS_SYSROOT=iphoneos
        IOS_ARCH=arm64
        IOS_OPENSSL_TARGET=ios64-xcrun
        IOS_VERSION_MIN_FLAG=-mios-version-min
        ;;
    simulator)
        IOS_SYSROOT=iphonesimulator
        IOS_ARCH=x86_64
        IOS_OPENSSL_TARGET=iossimulator-x86_64-xcrun
        IOS_VERSION_MIN_FLAG=-mios-simulator-version-min
        ;;
    *)
        echo "IOS_PLATFORM must be device or simulator, not $IOS_PLATFORM" >&2
        exit 1
        ;;
esac
# the minimum iOS version supported by Qt, used where Qt's toolchain file doesn't set it (OpenSSL)
IOS_DEPLOYMENT_TARGET=17.0
