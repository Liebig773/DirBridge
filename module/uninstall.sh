#!/system/bin/sh
MODDIR=${0%/*}
"$MODDIR/bin/dirbridge" stop
# Keep configuration/diagnostics. Never recursively delete export directories.
