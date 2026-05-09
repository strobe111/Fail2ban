# Changelog

All notable changes to F2BHub are documented here.

## v0.5.0 - 2026-05-10

### New
- Full-screen 3D globe background: Globe.gl renders behind all UI content with night-sky starfield
- Glassmorphism left panel: semi-transparent backdrop-filter blur design lets stars show through
- SPA navigation: page links (概览/服务器/封禁记录) swap content via fetch without reloading the globe
- Right-shifted earth: overflow:hidden container with inner element offset positions earth on right side
- Country labels with emoji flags showing active/total ban counts
- Navigation bar restored in top header (概览/服务器/封禁记录)
- Auto-rotating globe with drag-to-rotate and scroll-to-zoom interaction

### Changed
- Globe background image changed from transparent to night-sky.png (rotates with earth)
- Earth stats overlay panel removed (cleaner full-bleed design)
- Atmosphere color updated to cyan-blue (rgba(0,150,255,0.7))
- Auto-rotate speed lowered to 0.4 for smoother feel
- Arc/ring colors switched to cyan (#00ffff) theme
- Content panel scrollbar hidden for cleaner look

### Fixed
- Globe mouse interaction: pointer-events pass through transparent layout to canvas
- White scrollbar on left panel removed
- SPA routing preserves globe animation state across page transitions

---

## v0.4.0 - 2026-05-08

### New
- 3D Globe visualization: interactive globe.gl map showing ban origins by country
- `/api/globe` endpoint: returns country-level ban statistics (total + active bans)
- GeoIP module (app/geoip.py): IP-to-country lookup via ip-api.com with caching
- Globe toggle button in bottom-right corner, opens right-side drawer panel
- Responsive: desktop 50% slide-in, mobile bottom sheet
- Country labels show code + active/total ban count
- Arc connections from first registered country to all ban origins
- Active bans shown in red, inactive in blue
- Auto-refresh every 60 seconds while open

---

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