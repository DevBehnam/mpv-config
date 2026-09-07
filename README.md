# mpv-config

mpv configuration for Windows, with a one-line installer that sets up a fully portable build inside the given folder.

## Install

Run this in PowerShell (Windows, PowerShell 7+):

```powershell
irm https://raw.githubusercontent.com/DevBehnam/mpv-config/main/install.ps1 | iex
```

## Credits

This configuration builds on top of:

- [mpv](https://github.com/mpv-player/mpv) — the media player
- [uosc](https://github.com/tomasklaen/uosc) — the on-screen UI/controls
- [thumbfast](https://github.com/po5/thumbfast) — high-performance seek thumbnails
- [delete_current_file](https://github.com/stax76/mpv-scripts) — quick delete-current-file script
