# mpv-config

[mpv](https://github.com/mpv-player/mpv) configuration for Windows, with a one-line installer that sets up a fully portable build inside the given folder.

## Dependencies

*if you're intalling these for the first time, you might need to sign out and back in (or restart) to update the `%PATH%` and allow mpv to find them.*

### ffmpeg

```powershell
winget install -e --id Gyan.FFmpeg
```

### yt-dlp

```powershell
winget install -e --id yt-dlp.yt-dlp   
```

## Install

Windows, PowerShell 7+

```powershell
irm https://raw.githubusercontent.com/DevBehnam/mpv-config/main/install.ps1 | iex
```

## Credits

This configuration makes use of:
- [uosc](https://github.com/tomasklaen/uosc)
- [thumbfast](https://github.com/po5/thumbfast) 
- [delete_current_file](https://github.com/stax76/mpv-scripts)
- [kebind-visulizer](https://github.com/v-amorim/moonlight-mpv#keybind-visualizerlua)
- [sub-seek script](https://github.com/v-amorim/moonlight-mpv#sub-seeklua)
- [mpv-ytdlAutoFormat](https://github.com/Samillion/mpv-ytdlautoformat)
- [ytsub](https://github.com/Idlusen/mpv-ytsub/)
