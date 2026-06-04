# Changelog

All notable changes to `mainwp` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-06-04

### Added
- Initial release.
- `mainwp init` guided setup with gum prompts and a connectivity check
  against `/sites/basic`.
- Profile-based configuration stored in `~/.config/mainwp/config.json`
  with `0600` permissions. Supports `default`, custom profiles, and
  `MAINWP_URL`/`MAINWP_API_KEY` env overrides.
- Commands covering every documented v2 endpoint:
  - `sites` (list, basic, count, get, security, non-mainwp-changes,
    client, costs, plugins, themes, add, edit, sync, reconnect,
    disconnect, check, suspend, unsuspend, remove, plugin/theme actions)
  - `clients` (list, count, get, add, edit, remove, suspend, unsuspend,
    sites, sites-count, costs, fields)
  - `tags` (list, get, add, edit, remove, sites, clients)
  - `updates` (list, for-site, ignored, site-ignored, run-all, run-site,
    wp, plugins, themes, translations, ignore-wp, ignore-plugins,
    ignore-themes)
  - `costs` (list, get, add, edit, remove, sites, clients)
  - `users` (list, create, edit, delete, update-admin-password, import)
  - `settings` (general, advanced, monitoring, emails, cost-tracker with
    product-types and payment-methods, insights, api-backups, tools
    including destroy-sessions, renew-connections,
    disconnect-all-sites, clear-activation-data, restore-info-messages)
  - `monitoring` (list, basic, count, get, heartbeat, incidents,
    incidents-count, check, settings, global-settings)
  - `api-keys` (list, add, edit, delete)
  - `posts` and `pages` (list, get, create, edit, update-status, delete)
  - `batch` (global batch orchestrator)
- Three output modes: gum-styled tables (default), `--plain` text, and
  `--json` for piping into `jq`.
- Static bash and zsh completion scripts via `mainwp completion`.
- Long-running requests wrapped in a `gum spin` spinner.
- Bash 3.2 compatibility (no `declare -g`; uses the printf + eval trick
  to share global arrays between functions).
