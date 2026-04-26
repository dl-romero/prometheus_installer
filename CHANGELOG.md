# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

All notable changes to this project will be documented in this file.

## [Unreleased]
- No changes yet.

## [0.1.0] - 2026-04-26

### Added
- Optional web basic-auth setup in the installer flow.
- Support for creating `/etc/prometheus/web.yml` during installation.
- Prometheus web API features enabled in service flags: `--web.enable-lifecycle` and `--web.enable-admin-api`.
- Service reload support via systemd `ExecReload` (SIGHUP).
- Optional firewalld setup for `9090/tcp`.
- Optional SELinux port policy setup for `9090`.
- New helper script `manage_prometheus_users.sh` to manage users in `/etc/prometheus/web.yml` with add, update, remove, and list actions.
- Optional `--reload` flag in `manage_prometheus_users.sh` to apply user changes immediately.

### Changed
- Installer now enables authentication by default.
- Default installer credentials are `promethueus` / `promethueus` unless overridden.
- Installer supports non-interactive execution via command-line flags.
- README updated with usage and examples for both scripts.

### Fixed
- Installer now copies default `prometheus.yml` before ownership changes.
- Generated web config YAML indentation corrected for compatibility.

[Unreleased]: https://github.com/dl-romero/prometheus_installer/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/dl-romero/prometheus_installer/releases/tag/v0.1.0
