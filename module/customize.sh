#!/system/bin/sh
[ "$KSU" = true ] || abort 'DirBridge requires KernelSU / KernelSU Next.'
[ "${API:-0}" -ge 29 ] || abort 'Requires Android 10 (API 29) or newer.'
[ -x /data/adb/ksu/bin/busybox ] || abort 'KernelSU BusyBox was not found.'
for applet in nsenter mount umount mountpoint flock timeout realpath base64 sha256sum stat; do
  /data/adb/ksu/bin/busybox --list | /data/adb/ksu/bin/busybox grep -qx "$applet" || abort "Missing BusyBox applet: $applet"
done
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm_recursive "$MODPATH/bin" 0 0 0755 0755
# KernelSU assigns WebUI permissions/context; do not override webroot.
ui_print 'DirBridge: no system overlay or metamodule required.'
ui_print 'Open the module WebUI after reboot and add download folders.'
ui_print 'Android 10–17: intended range, not a device-tested compatibility claim.'
