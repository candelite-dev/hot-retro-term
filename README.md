# hot-retro-term

A fork of [cool-retro-term](https://github.com/Swordfish90/cool-retro-term) — a CRT-aesthetic terminal emulator — extended with split panes, a command palette, and a unified CRT rendering pipeline.

## Screenshots

![Image](<https://i.imgur.com/TNumkDn.png>)
![Image](<https://i.imgur.com/hfjWOM4.png>)
![Image](<https://i.imgur.com/GYRDPzJ.jpg>)

## What's New

### Split Panes
Divide the terminal into multiple panes, each running its own shell session.

- Split right or down (up to 16 panes per tab)
- Drag the divider to resize
- Move focus between panes with directional shortcuts
- ASCII-rendered dividers and focus border — everything stays inside the CRT effect

### Command Palette
A fuzzy-searchable command palette rendered entirely in ASCII art using your terminal font. Access all commands, toggle CRT effects, switch profiles, and more — without leaving the keyboard.

### ASCII Tab Bar
The tab bar renders inside the CRT shader pipeline (not as native OS chrome), so it inherits all CRT effects including curvature, bloom, and scan lines. Appears automatically when more than one tab is open.

### Window Curvature
A barrel distortion effect applied to the entire window — including the tab bar and all split panes — giving the whole interface a single unified CRT curve.

### Unified CRT Rendering
In split or multi-tab mode, all panes are composited under a single CRT shader pass, ensuring consistent visual effects across panes rather than each pane having its own independent effect bubble.

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| New tab | Ctrl+Shift+T |
| Close tab | Ctrl+Shift+W |
| Switch to tab N | Alt+N |
| Split right | Ctrl+Shift+D |
| Split down | Ctrl+Shift+H |
| Move focus left/right/up/down | Ctrl+Shift+←/→/↑/↓ |
| Command palette | Ctrl+Shift+P |
| Zoom in / out | Ctrl++ / Ctrl+- |

## Building

**Requirements**: Qt 6.10.0+ with `qt5compat` and `qtshadertools` modules.

```bash
qmake && make
./cool-retro-term
```

For platform-specific dependency setup, see the upstream wiki:
- [Linux build instructions](https://github.com/Swordfish90/cool-retro-term/wiki/Build-Instructions-(Linux))
- [macOS build instructions](https://github.com/Swordfish90/cool-retro-term/wiki/Build-Instructions-(macOS))

## Credits

Based on [cool-retro-term](https://github.com/Swordfish90/cool-retro-term) by [Swordfish90](https://github.com/Swordfish90).
Terminal emulation via [qmltermwidget](https://github.com/Swordfish90/qmltermwidget) (Konsole-derived).

## License

GPL-2.0 / GPL-3.0 — see `gpl-2.0.txt` and `gpl-3.0.txt`.
