#!/bin/sh
# Actual kernel bind-mount test. Run ONLY in an isolated mount namespace:
# sudo unshare --mount --propagation private sh tests/linux-mount.sh
set -eu
BASE=$(mktemp -d /tmp/dirbridge-mount.XXXXXX)
PROJECT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$PROJECT/module/bin/lib.sh"
LOWER=$BASE/media
EXPORT=$LOWER/Movies/DirBridge
STATE=$BASE/state
MODDIR=$BASE/module
CONFIG=$BASE/config
NSKEY=$(readlink /proc/self/ns/mnt)
mkdir -p "$LOWER/Android/data/example.app/files/Video Files" "$STATE/registry" "$STATE/stage" "$MODDIR"
src="$LOWER/Android/data/example.app/files/Video Files"
target="$EXPORT/Video Files"
cleanup() {
  # Only test-owned mount points, no recursive deletion of a mounted tree.
  umount "$target" 2>/dev/null || true
  for p in "$STATE/stage/"*; do [ ! -d "$p" ] || umount "$p" 2>/dev/null || true; done
  case "$BASE" in /tmp/dirbridge-mount.*) rm -rf -- "$BASE";; esac
}
trap cleanup EXIT HUP INT TERM
printf 'original' > "$src/video.mp4"
printf '# empty configuration\n' > "$CONFIG"
mount_one m1 'Video Files' '/sdcard/Android/data/example.app/files/Video Files'
is_mounted "$target" && is_readonly "$target"
[ "$(cat "$target/video.mp4")" = original ]
[ "$(identity "$src/video.mp4")" = "$(identity "$target/video.mp4")" ]
if (printf 'bad' > "$target/video.mp4") 2>/dev/null; then echo 'ERROR: export was writable'; exit 1; fi
printf 'updated' > "$src/video.mp4"
[ "$(cat "$target/video.mp4")" = updated ]
printf 'new' > "$src/new.mp4"
[ "$(cat "$target/new.mp4")" = new ]
cleanup_obsolete
! is_mounted "$target"
[ "$(cat "$src/video.mp4")" = updated ]
echo 'PASS: real bind mount, same inode, read-only alias, writable live source, clean detach'
