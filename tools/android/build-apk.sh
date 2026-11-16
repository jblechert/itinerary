#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
# SPDX-License-Identifier: BSD-3-Clause
#
# Build an Itinerary APK locally, mirroring KDE's craft-android CI job.
#
# Usage: tools/android/build-apk.sh [arm64|x86_64] [deps|app|package|all|shell]
#   deps     install dependencies (prebuilt from the KDE Craft cache where possible)
#   app      build itinerary from this checkout
#   package  produce the APK (unsigned) in the workspace apk/ dir
#   all      deps + app + package (default)
#   shell    open a shell in the build container
#
# Workspace (craft root, downloads, build dirs) lives next to the checkout in ../itinary-craft (override with ITINERARY_CRAFT_DIR); it must stay outside the source tree, as packaging scans the tree for AndroidManifest files.
set -euo pipefail

ARCH="${1:-arm64}"
STEP="${2:-all}"
IMAGE="${ITINERARY_ANDROID_IMAGE:-invent-registry.kde.org/sysadmin/ci-images/android-qt611:latest}"

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WS="${ITINERARY_CRAFT_DIR:-$(dirname "$SRC")/itinary-craft}"
TARGET="android-${ARCH}-clang"

mkdir -p "$WS/downloads"
[ -d "$WS/craftmaster" ] || git clone https://invent.kde.org/packaging/craftmaster.git "$WS/craftmaster"
[ -d "$WS/craft-ci" ]    || git clone --depth=1 https://invent.kde.org/sysadmin/craft-ci.git "$WS/craft-ci"

# Local overrides on top of KDE's CI config: download dir inside the workspace.
cat > "$WS/local-override.ini" <<EOF
[$TARGET]
Paths/DownloadDir = /craft/downloads/
EOF

read -r -d '' INNER <<'EOF' || true
set -euo pipefail
# NDK in the image is owner-only executable, so we run as root and hand files back.
trap 'chown -R "$HOST_UID:$HOST_GID" /craft' EXIT
git config --global --add safe.directory '*'
cd /craft
cm() {
  python3 -u craftmaster/CraftMaster.py \
    --config craft-ci/qt6/CraftConfig.ini \
    --config-override /src/.craft.ini \
    --config-override /craft/local-override.ini \
    --target "$TARGET" "$@"
}
OPTS=(--options itinerary.srcDir=/src)
case "$STEP" in
  deps)    cm --setup; cm -c -i craft; cm -c --install-deps itinerary ;;
  app)     cm -c --no-cache "${OPTS[@]}" itinerary ;;
  package) cm -c --package "${OPTS[@]}" itinerary
           ls -l /craft/*/apk/ 2>/dev/null || true ;;
  all)     cm --setup; cm -c -i craft; cm -c --install-deps itinerary
           cm -c --no-cache "${OPTS[@]}" itinerary
           cm -c --package "${OPTS[@]}" itinerary ;;
  shell)   bash ;;
  *) echo "unknown step: $STEP" >&2; exit 2 ;;
esac
EOF

TTY=()
[ -t 0 ] && TTY=(-it)

exec docker run --rm "${TTY[@]}" \
  --user 0:0 \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -e HOME=/craft/home -e TARGET="$TARGET" -e STEP="$STEP" \
  -v "$SRC:/src" \
  -v "$WS:/craft" \
  "$IMAGE" bash -c "mkdir -p /craft/home; $INNER"
