# Architecture

## Data path

`/storage/emulated/0/Android/data/<package>/...` is a user-facing source path. DirBridge validates it and resolves the corresponding `/data/media/0/...` directory. The export target is restricted to `/data/media/0/Movies/DirBridge/<alias>`.

The worker first bind-mounts the source into a root-only staging directory, makes that mount private and read-only (`nosuid,nodev,noexec`), then bind-mounts the read-only view to the export target. It verifies read-only mount flags and device/inode identity. The source remains writable at its original location. No file migration or per-file copying occurs.

The export is intended to be presented through the platform's existing emulated-storage layer at `/storage/emulated/0/Movies/DirBridge/<alias>`. A successful root mount alone does not prove that a FUSE daemon or player can read it.

## Namespaces and recovery

All external commands enter PID 1's mount namespace through KernelSU's BusyBox `nsenter`. Reconciliation processes that namespace first and then distinct namespaces of running `com.android.providers.media*`, `com.google.android.providers.media*`, and `/system/bin/sdcard` processes. The worker compares its actual namespace ID with the expected ID, so a vanished/reused process does not silently select a different namespace.

This explicitly addresses known storage services, not every possible vendor storage daemon. It neither injects into arbitrary player processes nor changes their UIDs, permissions, or SELinux policy. Vendor-specific namespaces remain an area for device testing.

`service.sh` backgrounds a daemon. It waits for boot completion outside critical boot stages, then reconciles every 60 seconds. `flock` prevents duplicate daemons and concurrent mutating commands. WebUI saves use a temporary file and atomic rename under the same control lock. The daemon retries missing sources and newly created service namespaces; it does not watch or scan every video file.

## Ownership and rollback

Root-only per-boot ownership records contain the export alias, selected lower source and source device/inode identity. The record is committed before an export is published. Cleanup only unmounts a read-only target matching one of these records; foreign mounts are skipped. Records are retained for the current boot to recognize cloned namespace views and replaced source directories.

An empty export directory is required. Existing user files are never hidden deliberately. No recursive copy, chmod, chown, deletion, source relocation, symlink creation, force unmount or lazy unmount is used by the module. Newly created export directories alone receive media ownership and mode 0775. Root-only state uses 0700/0600. If a player holds an export busy, cleanup is deferred, and the UI reports it.

Staging failure leaves no intentionally published writable view. Unexpected publication verification failures trigger an unmount attempt and an error status. Mount failures do not abort the Android boot. This is not a filesystem-level sandbox against a malicious privileged process: Root can always alter module state or mounts.

## Configuration protocol

Persistent configuration: `/data/adb/dirbridge/mappings.conf`.

```text
# DirBridge schema=1
<ID>|<enabled 0/1>|<UTF-8 alias in canonical base64>|<UTF-8 source in canonical base64>
```

There are at most 64 mappings, with unique IDs and aliases. The backend rejects control characters, NUL/trailing-newline base64 artifacts, `..`, repeated separators, backslashes, delimiters, private app storage, foreign users, output recursion and symlink-resolved source paths. The WebUI passes base64 data only to a fixed command; paths are never evaluated as shell code. Every filesystem variable is quoted. UI uses textContent for user data.

Runtime root: `/data/adb/dirbridge/runtime/<boot UUID>/`. No old boot's records authorize cleanup in a new boot. Small old per-boot state is retained for diagnosis; it contains no video data. A rolling log is capped on daemon/mutation log writes, and stdout status is atomically replaced on reconciliation.

Persistent `paused` survives reboot and reinstall. Module `disable` / `remove` flags and runtime `stop` halt recovery. Uninstallation retains configuration and does not delete the media export tree.

## Boundaries

- Main user 0, internal emulated storage only.
- API 29 minimum; no fixed upper API gate, to allow device testing on newer versions.
- No background MediaStore scan/broadcast over entire libraries. MX scans its configured folder.
- `.nomedia`, media permissions, MediaProvider policy, lower inode ownership, ROM SELinux policy and kernel differences can still prevent ordinary-player access.
- SDK detection is diagnostic, not a claim that the Android 17 storage implementation was exhaustively reviewed or tested.
- No networking, telemetry, hidden video enumeration, executable downloads, or bundled platform binaries.

## Verification layers

Portable shell tests mock mount syscalls and exercise path validation, journal ownership, read-only publication failure, idempotence and cleanup. Browser tests mock the KernelSU bridge and exercise actual DOM behavior at mobile widths. `tests/linux-mount.sh` checks real Linux bind mount semantics in a private namespace when run on Linux. Neither layer substitutes for Android / FUSE / SELinux / MX validation.
