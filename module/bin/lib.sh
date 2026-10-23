#!/system/bin/sh
# SPDX-License-Identifier: MIT
# This library has no side effects when sourced. Production paths are fixed
# by control.sh; test harnesses can substitute a disposable filesystem.
wait_lock() {
  # Android's KernelSU BusyBox supports -n, but not util-linux's -w.
  # Keep the caller's FD open so the acquired lock lasts for the operation.
  local waited=0 message rc
  while :; do
    message=$(flock -n "$1" 2>&1) && return 0
    rc=$?
    if [ -n "$message" ] || [ "$rc" -ne 1 ]; then
      printf 'Lock acquisition failed: %s (exit %s)\n' "$message" "$rc" >&2
      return 2
    fi
    if [ "$waited" -ge "$2" ]; then
      echo 'Another operation is running; retry shortly' >&2
      return 1
    fi
    sleep 1 || return 2
    waited=$((waited + 1))
  done
}
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
human_status() {
  local id enabled alias64 source64 extra name line kind code detail ns found count=0
  if [ -f "$DATA/paused" ]; then
    printf '\n当前已暂停全部映射。要继续使用，请在模块页面点“恢复全部”。\n'
  fi
  while IFS='|' read -r id enabled alias64 source64 extra; do
    case "$id" in ''|'#'*) continue;; esac
    name=$(decode "$alias64") || continue
    count=$((count + 1))
    if [ "$enabled" != 1 ]; then
      printf '\n[已停用] %s\n' "$name"
      continue
    fi
    if [ -f "$DATA/paused" ]; then
      printf '\n[已暂停] %s\n' "$name"
      continue
    fi
    # Prefer a failure/waiting report over a success in another namespace.
    line=''
    if [ -f "$STATE/status.txt" ]; then
      line=$(awk -F '|' -v wanted="$id" '
        $1=="S" && $2==wanted {
          score=($3=="error" || $3=="conflict" || $3=="busy") ? 4 : ($3=="waiting" ? 3 : ($3=="mounted" ? 2 : 1))
          if(score>best) {best=score; result=$0}
        } END {print result}' "$STATE/status.txt")
    fi
    IFS='|' read -r kind found code detail ns <<EOF
$line
EOF
    case "$code" in
      mounted) printf '\n[已挂载] %s\n  播放器入口：/storage/emulated/0/Movies/DirBridge/%s\n' "$name" "$name";;
      waiting) printf '\n[等待源目录] %s\n  %s\n' "$name" "$(decode "$detail")";;
      error|conflict|busy) printf '\n[需要处理] %s\n  %s\n' "$name" "$(decode "$detail")";;
      *) printf '\n[尚未建立映射] %s\n  请打开模块页面查看状态。\n' "$name";;
    esac
  done < "$CONFIG"
  [ "$count" -ne 0 ] || printf '\n还没有添加目录，请打开模块页面，点击“添加目录”。\n'
  if [ -f "$STATE/status.txt" ]; then
    while IFS='|' read -r kind id code detail ns; do
      [ "$kind" = S ] && [ "$id" = '-' ] || continue
      printf '\n[提示] %s\n' "$(decode "$detail")"
    done < "$STATE/status.txt"
  fi
  printf '\n打开 MX Player 或其他本地播放器查看视频。\n如果找不到，请刷新列表，或手动添加目录：\n/storage/emulated/0/Movies/DirBridge\n'
}
decode() {
  local v
  case "$1" in *[!A-Za-z0-9+/=]*|'') return 1;; esac
  v=$(printf '%s' "$1" | base64 -d 2>/dev/null) || return 1
  # Round-trip rejects NULs and trailing newlines lost by shell substitution.
  [ "$(b64 "$v")" = "$1" ] || return 1
  printf '%s' "$v"
}
clean_text() {
  [ -n "$1" ] && [ "${#1}" -le "$2" ] || return 1
  case "$1" in *'|'*|*'\'*|*'
'*) return 1;; esac
  ! printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'
}
valid_alias() {
  clean_text "$1" 180 || return 1
  case "$1" in .*|*/*|' '*|*' ') return 1;; esac
}
normal_source() {
  local p=$1
  case "$p" in
    /sdcard/*) p="/storage/emulated/0/${p#/sdcard/}";;
    /data/media/0/*) p="/storage/emulated/0/${p#/data/media/0/}";;
  esac
  while [ "${p%/}" != "$p" ]; do p=${p%/}; done
  printf '%s' "$p"
}
valid_source() {
  local p rest pkg
  p=$(normal_source "$1")
  clean_text "$p" 1024 || return 1
  case "$p/" in *'/../'*|*'/./'*|*'//'*) return 1;; esac
  case "$p" in
    /storage/emulated/0/Android/data/*/*|/storage/emulated/0/Android/media/*/*)
      rest=${p#/storage/emulated/0/Android/}; rest=${rest#*/}; pkg=${rest%%/*}
      case "$pkg" in ''|*[!a-zA-Z0-9._]*) return 1;; esac;;
    /storage/emulated/0/Download/*|/storage/emulated/0/Movies/*|/storage/emulated/0/DCIM/*) :;;
    *) return 1;;
  esac
  # Never allow recursive exports or any parent of the export root.
  case "$p/" in /storage/emulated/0/Movies/DirBridge/*) return 1;; esac
  printf '%s' "$p"
}
valid_browse() {
  local p=$1
  clean_text "$p" 1024 || return 1
  case "$p/" in *'/../'*|*'/./'*|*'//'*) return 1;; esac
  case "$p" in
    /storage/emulated/0/Android/data|/storage/emulated/0/Android/media|/storage/emulated/0/Download|/storage/emulated/0/Movies|/storage/emulated/0/DCIM) return 0;;
    /storage/emulated/0/Android/data/*|/storage/emulated/0/Android/media/*|/storage/emulated/0/Download/*|/storage/emulated/0/Movies/*|/storage/emulated/0/DCIM/*) return 0;;
  esac
  return 1
}
validate_config() {
  local file=$1 line id enabled alias64 source64 extra alias source ids='|' aliases='|' n=0
  [ "$(wc -c < "$file")" -le 98304 ] || { echo 'Configuration too large' >&2; return 1; }
  [ "$(awk 'NF && $0 !~ /^#/ {n++} END {print n+0}' "$file")" -le 64 ] || { echo 'Maximum 64 mappings' >&2; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue;; esac
    IFS='|' read -r id enabled alias64 source64 extra <<EOF
$line
EOF
    case "$id" in ''|*[!a-zA-Z0-9_-]*) echo 'Invalid mapping ID' >&2; return 1;; esac
    [ "${#id}" -le 48 ] && [ "$line" = "$id|$enabled|$alias64|$source64" ] || return 1
    case "$enabled" in 0|1) :;; *) return 1;; esac
    alias=$(decode "$alias64") && valid_alias "$alias" || { echo 'Invalid folder name' >&2; return 1; }
    source=$(decode "$source64") || { echo '源目录编码校验失败，请重新选择目录' >&2; return 1; }
    # Capture the normalized path. The device's BusyBox ash can return a
    # spurious failure for this function redirected to /dev/null in a read loop.
    source=$(valid_source "$source") || { echo '源目录不在支持范围内，或路径格式无效' >&2; return 1; }
    case "$ids" in *"|$id|"*) echo 'Duplicate mapping ID' >&2; return 1;; esac
    case "$aliases" in *"|$alias64|"*) echo 'Duplicate export name' >&2; return 1;; esac
    ids="$ids$id|"; aliases="$aliases$alias64|"; n=$((n + 1))
    [ "$n" -le 64 ] || { echo 'Maximum 64 mappings' >&2; return 1; }
  done < "$file"
}
identity() { stat -Lc '%d:%i' "$1" 2>/dev/null; }
mount_info_lines() { cat /proc/self/mountinfo; }
mount_entry() {
  # Newlines/backslashes are forbidden by validation; only spaces need escaping.
  local p
  p=$(printf '%s' "$1" | sed 's/ /\\040/g')
  mount_info_lines | DB_MOUNT_PATH="$p" awk '$5 == ENVIRON["DB_MOUNT_PATH"] {line=$0} END {if(line != "") print line}'
}
is_mounted() { [ -n "$(mount_entry "$1")" ]; }
is_readonly() {
  local opts
  opts=$(mount_entry "$1" | awk '{print $6}')
  case ",$opts," in *,ro,*) return 0;; esac
  return 1
}
safe_export_root() {
  local real
  [ -d "$LOWER" ] && [ ! -L "$LOWER/Movies" ] && [ ! -L "$EXPORT" ] || return 1
  [ ! -e "$LOWER/Movies" ] || [ -d "$LOWER/Movies" ] || return 1
  if [ ! -d "$LOWER/Movies" ]; then
    mkdir "$LOWER/Movies" || return 1
    chown 1023:1023 "$LOWER/Movies"; chmod 0775 "$LOWER/Movies"
  fi
  if [ ! -d "$EXPORT" ]; then
    mkdir "$EXPORT" || return 1
    chown 1023:1023 "$EXPORT"; chmod 0775 "$EXPORT"
  fi
  real=$(realpath "$EXPORT") || return 1
  [ "$real" = "$EXPORT" ]
}
safe_target() {
  valid_alias "$1" && safe_export_root || return 1
  local target="$EXPORT/$1"
  [ ! -L "$target" ] || return 1
  if [ ! -e "$target" ]; then
    mkdir "$target" || return 1
    chown 1023:1023 "$target"; chmod 0775 "$target"
  fi
  [ -d "$target" ] && [ "$(realpath "$target")" = "$target" ]
}
resolve_lower() {
  local p canonical expected
  p=$(valid_source "$1") || return 1
  expected="$LOWER/${p#/storage/emulated/0/}"
  [ -d "$expected" ] || return 2
  canonical=$(realpath "$expected") || return 2
  # Reject symlinks instead of exposing destinations outside the selected tree.
  [ "$canonical" = "$expected" ] || return 3
  printf '%s' "$canonical"
}
owned_mount() {
  local target=$1 item a s ident current wanted
  is_mounted "$target" && is_readonly "$target" || return 1
  current=$(identity "$target") || return 1
  wanted=$(b64 "${target##*/}")
  for item in "$STATE/registry/"*; do
    [ -f "$item" ] || continue
    IFS='|' read -r a s ident < "$item"
    [ "$a" = "$wanted" ] && [ "$ident" = "$current" ] && return 0
  done
  return 1
}
remember_mount() {
  local alias=$1 source=$2 ident=$3 key tmp
  key=$(printf '%s|%s|%s' "$alias" "$source" "$ident" | sha256sum | cut -d ' ' -f 1)
  tmp="$STATE/registry/.$key.$$"
  printf '%s|%s|%s\n' "$(b64 "$alias")" "$(b64 "$source")" "$ident" > "$tmp" || return 1
  mv -f "$tmp" "$STATE/registry/$key"
}
active_source_for() {
  local wanted id en a s extra
  wanted=$(b64 "$1")
  [ ! -f "$STATE/paused" ] && [ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ] && [ ! -f "$STATE/stop" ] || return 1
  while IFS='|' read -r id en a s extra; do
    [ "$en" = 1 ] && [ "$a" = "$wanted" ] || continue
    decode "$s"; return
  done < "$CONFIG"
  return 1
}
report() { printf 'S|%s|%s|%s|%s\n' "$1" "$2" "$(b64 "$3")" "$NSKEY"; }
cleanup_obsolete() {
  local item a s ident alias target want actual
  for item in "$STATE/registry/"*; do
    [ -f "$item" ] || continue
    IFS='|' read -r a s ident < "$item"
    alias=$(decode "$a") && valid_alias "$alias" || continue
    target="$EXPORT/$alias"
    [ ! -L "$target" ] && is_mounted "$target" || continue
    want=$(active_source_for "$alias")
    actual=$(resolve_lower "$want" 2>/dev/null)
    if [ -n "$actual" ] && [ "$(identity "$actual")" = "$(identity "$target")" ] && owned_mount "$target"; then continue; fi
    if owned_mount "$target"; then
      # No lazy or force unmount: open playback may postpone removal.
      umount "$target" 2>/dev/null || report '-' busy "目录正在使用，停止播放后重试：$alias"
    else
      report '-' conflict "跳过非本模块拥有的挂载：$alias"
    fi
  done
}
mount_one() {
  local id=$1 alias=$2 input=$3 source rc target ident stage
  source=$(resolve_lower "$input"); rc=$?
  case "$rc" in 0) :;; 2) report "$id" waiting '源目录尚不存在或手机未解锁'; return;; *) report "$id" error '源目录无效，或经过符号链接'; return;; esac
  safe_target "$alias" || { report "$id" error '目标路径不安全或不可创建'; return; }
  target="$EXPORT/$alias"; ident=$(identity "$source")
  if is_mounted "$target"; then
    if owned_mount "$target" && [ "$(identity "$target")" = "$ident" ]; then
      report "$id" mounted '只读挂载已建立；播放器可读性请实际验证'
    else report "$id" conflict '目标已有其他挂载或旧映射正被使用'; fi
    return
  fi
  [ -z "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit)" ] || { report "$id" conflict '目标目录非空，拒绝覆盖已有文件'; return; }
  stage="$STATE/stage/$NSKEY-$id"
  mkdir -p "$stage" || { report "$id" error '无法创建暂存挂载点'; return; }
  # A killed worker can leave its private stage; this directory is root-only.
  if is_mounted "$stage"; then umount "$stage" || { report "$id" error '暂存挂载忙'; return; }; fi
  if ! mount -o bind "$source" "$stage" || ! mount --make-private "$stage" || ! mount -o remount,bind,ro,nosuid,nodev,noexec "$stage" || ! is_readonly "$stage"; then
    umount "$stage" 2>/dev/null
    report "$id" error '无法建立只读映射，未开放播放器入口'; return
  fi
  # Write ownership journal before publishing, to recover from interruption.
  if ! remember_mount "$alias" "$source" "$ident" || ! mount -o bind "$stage" "$target"; then
    umount "$stage" 2>/dev/null
    report "$id" error '发布映射失败'; return
  fi
  if ! mount --make-private "$target" || ! is_readonly "$target" || [ "$(identity "$target")" != "$ident" ]; then
    umount "$target" 2>/dev/null
    umount "$stage" 2>/dev/null
    report "$id" error '映射校验失败，已请求撤回'; return
  fi
  umount "$stage" 2>/dev/null
  report "$id" mounted '只读挂载已建立；播放器可读性请实际验证'
}
worker() {
  local id en a s extra alias source
  [ "$(readlink /proc/self/ns/mnt)" = "$NSKEY" ] || { echo 'Namespace changed; retry later' >&2; return 1; }
  validate_config "$CONFIG" || return 1
  safe_export_root || { report '-' waiting '共享存储未就绪或目标目录路径异常'; return; }
  cleanup_obsolete
  while IFS='|' read -r id en a s extra; do
    case "$id" in ''|'#'*) continue;; esac
    alias=$(decode "$a"); source=$(decode "$s")
    if [ "$en" != 1 ] || [ -f "$STATE/paused" ] || [ -f "$STATE/stop" ] || [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then
      report "$id" disabled '映射已停用'; continue
    fi
    mount_one "$id" "$alias" "$source"
  done < "$CONFIG"
}
