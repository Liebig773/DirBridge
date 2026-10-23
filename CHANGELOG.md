# Changelog

## 0.1.3 — 2026-10-22

- Replace the KernelSU action button protocol output with Chinese per-directory results and player instructions.
- Clarify startup restoration and show automatic player discovery before manual folder setup.
- Simplify module description and UI footer; preserve detailed validation limits in developer documentation.

## 0.1.2 — 2026-10-22

- Fix valid source paths rejected during configuration validation on KernelSU BusyBox 1.36.1.1: capture normalized paths instead of redirecting the validator to /dev/null in a read loop.
- Distinguish malformed source encoding from invalid source paths.
- Reproduced on 2211133C / Android 17 / HyperOS OS4.0.0.12.XMCCNXM.

## 0.1.1 — 2026-10-22

- Fix KernelSU BusyBox 1.36.1 rejecting `flock -w`: retry nonblocking `flock -n` for up to 10 seconds instead.
- Report lock command failures separately from genuine contention.
- Preserve saved mappings and existing mount behavior.
- Add regression coverage for lock success, contention, timeout and command errors.

## 0.1.0 — 2026-10-22

- First source-available MIT release for device validation.
- KernelSU module with Chinese WebUI and multiple read-only download-directory mappings.
- Boot recovery, missing-source retries and known storage-service namespace handling.
- Root-owned ownership journal, non-empty target protection, deferred busy unmount.
- Portable shell, browser and optional real Linux mount tests.
- Intended Android 10–17 range; no Android device compatibility claimed yet.
