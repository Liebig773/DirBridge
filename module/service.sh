#!/system/bin/sh
MODDIR=${0%/*}
"$MODDIR/bin/dirbridge" daemon >/dev/null 2>&1 &
