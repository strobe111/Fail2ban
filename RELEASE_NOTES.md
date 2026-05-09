# Release Notes - v0.5.0

## Full-Screen Globe Dashboard

### New
- **Full-screen 3D globe background**: Globe.gl renders behind all UI content with night-sky starfield that rotates with the earth
- **Glassmorphism left panel**: Semi-transparent backdrop-filter blur design lets stars show through content area
- **SPA navigation**: Page links (概览/服务器/封禁记录) swap content via fetch without reloading the globe — background animation stays intact
- **Right-shifted earth**: overflow:hidden container with inner element offset positions earth on right side of screen
- **Country labels with emoji flags**: Each ban origin shows flag emoji + country code + active/total ban counts
- **Navigation bar**: Restored in top header (概览/服务器/封禁记录)
- **Interactive globe**: Auto-rotating with drag-to-rotate and scroll-to-zoom

### Changed
- Globe background image changed from transparent to night-sky.png (rotates with earth, single-layer universe)
- Earth stats overlay panel removed (cleaner full-bleed design)
- Atmosphere color updated to cyan-blue theme
- Auto-rotate speed lowered to 0.4 for smoother feel
- Arc/ring colors switched to cyan (#00ffff)
- Content panel scrollbar hidden for cleaner look

### Fixed
- Globe mouse interaction: pointer-events pass through transparent layout to canvas for drag/zoom
- White scrollbar on left panel removed
- SPA routing preserves globe animation state across page transitions