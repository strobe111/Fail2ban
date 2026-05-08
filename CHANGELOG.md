# Changelog

All notable changes to F2BHub are documented here.

## v0.3.0 - 2026-05-08

### New
- Threat legend moved inline next to server list title (no more separate block)
- `f2b.sh` is now the single entry point — `curl | bash` downloads, clones, and runs
- One-click install via `curl -sSL .../f2b.sh | bash`
- Full root user support — auto-creates `f2bhub` system user for services
- `as_root()` helper: runs commands directly as root, or via sudo for non-root

### Fixed
- Threat timeline colors now use local time instead of UTC — bans in the current hour actually show yellow/red
- Agent `agent.conf` heredoc no longer leaks EOF markers
- `f2b.sh` piped via curl: stdin re-attached to terminal so interactive menu works
- `git clone` no longer loses executable bit — `chmod +x` added before exec
- Bootstrap handles corrupted `/opt/F2BHub` (non-git directory) — removes and re-clones
- `is_online` check uses local time for consistent comparison

---

## v0.2.0 - 2026-05-07

### New
- Fail2ban Agent: push ban/unban records to central Hub
- Agent heartbeat for server online status monitoring
- Web dashboard: servers list, server detail, bans page
- Threat level visualization (8-hour timeline)
- IP address masking in UI
- Agent remote install via API endpoint

### Changed
- Host binding changed to `0.0.0.0:5001` (was `127.0.0.1`)
- Debug mode disabled for production

---

## v0.1.0 - 2026-05-07

### New
- Initial release: Flask web panel with SQLite backend
- Multi-server ban record aggregation
- Interactive management script (`f2b.sh`)