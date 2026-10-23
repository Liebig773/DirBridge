#!/system/bin/sh
# SPDX-License-Identifier: MIT
umask 077
MODDIR=$(CDPATH= cd -- "${0%/*}/.." && pwd) || exit 1
BB=/data/adb/ksu/bin/busybox
DATA=/data/adb/dirbridge
LOWER=/data/media/0
EXPORT=$LOWER/Movies/DirBridge
CONFIG=$DATA/mappings.conf
BOOT=$(cat /proc/sys/kernel/random/boot_id) || exit 1
case "$BOOT" in ''|*[!a-f0-9-]*) exit 1;; esac
STATE=$DATA/runtime/$BOOT
export ASH_STANDALONE=1
. "$MODDIR/bin/lib.sh"
[ "$(id -u)" = 0 ] || { echo 'Root required' >&2; exit 1; }
mkdir -p "$DATA" "$STATE/registry" "$STATE/stage" || exit 1
chmod 0700 "$DATA" "$STATE" "$STATE/registry" "$STATE/stage"
[ -e "$CONFIG" ] || printf '# DirBridge schema=1\n' > "$CONFIG"
# Persistent pause survives reboot; runtime stop only lasts for this boot.
[ ! -f "$DATA/paused" ] || touch "$STATE/paused"

lock() {
  exec 9>"$DATA/control.lock" || exit 1
  wait_lock 9 10 || exit 1
}
trim_log() {
  if [ -f "$DATA/last.log" ] && [ "$(wc -c < "$DATA/last.log")" -gt 65536 ]; then
    tail -c 32768 "$DATA/last.log" > "$DATA/log.tmp" && mv -f "$DATA/log.tmp" "$DATA/last.log"
  fi
}
note() {
  trim_log
  printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$DATA/last.log"
}
apply_all() {
  local proc pid cmd key seen='|' result="$STATE/status.tmp" mainkey ok=0
  trim_log
  validate_config "$CONFIG" || { note 'Configuration rejected; mounts unchanged'; return 1; }
  : > "$result"
  # Main namespace first, followed by storage services with private namespaces.
  # No entering arbitrary player/app namespaces and no app privilege changes.
  for proc in /proc/1 /proc/[0-9]*; do
    pid=${proc##*/}
    if [ "$pid" != 1 ]; then
      cmd=$(tr '\000' '\n' < "$proc/cmdline" 2>/dev/null | head -n 1)
      case "$cmd" in com.android.providers.media*|com.google.android.providers.media*|/system/bin/sdcard) :;; *) continue;; esac
    fi
    key=$(readlink "$proc/ns/mnt" 2>/dev/null) || continue
    case "$seen" in *"|$key|"*) continue;; esac
    seen="$seen$key|"
    if "$BB" timeout 40 "$BB" nsenter -t "$pid" -m "$BB" sh "$MODDIR/bin/control.sh" worker "$key" >> "$result" 2>> "$DATA/last.log"; then
      ok=$((ok + 1))
    else
      printf 'S|-|error|%s|%s\n' "$(b64 "无法处理媒体服务挂载环境 PID=$pid；稍后自动重试")" "$key" >> "$result"
    fi
  done
  mv -f "$result" "$STATE/status.txt"
  date '+%F %T' > "$STATE/applied_at"
  [ "$ok" -gt 0 ] || return 1
}
status() {
  local paused=0 running=0 applied='' config64
  [ ! -f "$DATA/paused" ] || paused=1
  # Holding this lock is the daemon liveness check, not a stale PID file.
  ( exec 8>"$DATA/daemon.lock"; flock -n 8 ) || running=1
  [ ! -f "$STATE/applied_at" ] || applied=$(cat "$STATE/applied_at")
  printf 'ENV|%s|%s|%s|%s|%s|%s\n' "$(getprop ro.build.version.sdk)" "$(b64 "$(getprop ro.build.version.release)")" "$(b64 "$(getprop ro.product.model)")" "$paused" "$running" "$(b64 "$applied")"
  printf 'CFG|%s\n' "$(base64 < "$CONFIG" | tr -d '\n')"
  [ ! -f "$STATE/status.txt" ] || cat "$STATE/status.txt"
}
browse() {
  local public lower resolved child name n=0
  public=$(decode "$1") || return 1
  public=$(normal_source "$public")
  valid_browse "$public" || { echo 'Folder is outside allowed shared storage roots' >&2; return 1; }
  lower="$LOWER/${public#/storage/emulated/0/}"
  [ -d "$lower" ] && [ "$(realpath "$lower")" = "$lower" ] || { echo 'Folder missing, locked, or symlinked' >&2; return 1; }
  printf 'P|%s\n' "$(b64 "$public")"
  for child in "$lower"/*; do
    [ -d "$child" ] && [ ! -L "$child" ] || continue
    name=${child##*/}; clean_text "$name" 255 || continue
    [ "$public/$name" != /storage/emulated/0/Movies/DirBridge ] || continue
    printf 'D|%s|%s\n' "$(b64 "$name")" "$(b64 "$public/$name")"
    n=$((n + 1)); [ "$n" -lt 500 ] || { printf 'TRUNCATED\n'; break; }
  done
}
diagnose() {
  printf 'DirBridge v0.1.3 — diagnostics (contains configured paths, no file contents)\n'
  status
  printf '\nKernel: '; uname -r
  printf 'SELinux: '; getenforce 2>/dev/null
  printf 'Namespace: '; readlink /proc/self/ns/mnt
  printf '\nExport mount entries (init namespace):\n'
  awk 'index($5,"/data/media/0/Movies/DirBridge/")==1 {print}' /proc/self/mountinfo
  printf '\nRecent log:\n'
  [ ! -f "$DATA/last.log" ] || tail -n 80 "$DATA/last.log"
  printf '\nMounted does not prove MX readability. Check MX all-files/video permission, hidden files and .nomedia settings.\n'
}

case "${1:-status}" in
  action)
    printf 'DirBridge · 目录映射\n正在重新应用已保存的目录，请稍候…\n'
    # Keep machine protocol and low-level command output in the diagnostic log.
    if ! (lock; apply_all) >> "$DATA/last.log" 2>&1; then
      printf '\n本次应用未完成，请稍后重试，或在模块页面查看诊断。\n'
      exit 1
    fi
    printf '\n本次处理完成，各目录状态如下：\n'
    human_status
    ;;
  worker) NSKEY=$2; worker;;
  status) status;;
  browse) browse "$2";;
  diagnose) diagnose;;
  save)
    lock
    [ "${#2}" -le 131072 ] || exit 1
    tmp="$DATA/config.$$.tmp"
    trap 'rm -f "$tmp"' EXIT HUP INT TERM
    # Outer base64 can encode a final newline; inner fields are strict.
    case "$2" in *[!A-Za-z0-9+/=]*|'') echo 'Invalid configuration encoding' >&2; exit 1;; esac
    printf '%s' "$2" | base64 -d > "$tmp" || exit 1
    validate_config "$tmp" || exit 1
    cp "$CONFIG" "$DATA/mappings.previous.conf" || exit 1
    mv -f "$tmp" "$CONFIG" || exit 1
    note 'Configuration saved'
    echo 'SAVED'
    ;;
  apply) lock; apply_all && echo 'APPLIED';;
  pause)
    lock
    case "$2" in
      1) touch "$DATA/paused" "$STATE/paused";;
      0) rm -f "$DATA/paused" "$STATE/paused" "$STATE/stop";;
      *) exit 1;;
    esac
    apply_all
    ;;
  stop)
    lock; touch "$DATA/paused" "$STATE/paused" "$STATE/stop"; apply_all
    ;;
  daemon)
    exec 8>"$DATA/daemon.lock"
    flock -n 8 || exit 0
    rm -f "$STATE/stop"
    while [ "$(getprop sys.boot_completed)" != 1 ]; do
      [ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ] || exit 0
      sleep 10
    done
    note 'Daemon started; 60-second recovery interval'
    while :; do
      "$BB" sh "$MODDIR/bin/control.sh" apply >/dev/null 2>> "$DATA/last.log"
      [ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ] && [ ! -f "$STATE/stop" ] || break
      sleep 60
    done
    note 'Daemon stopped'
    ;;
  *) echo 'Usage: dirbridge status|apply|diagnose|browse BASE64_PATH|save BASE64_CONFIG|pause 0/1' >&2; exit 1;;
esac
