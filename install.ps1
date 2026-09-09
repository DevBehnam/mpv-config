#Requires -Version 7.0

<#
.SYNOPSIS
    Installs the mpv configuration and its required third-party components.

.DESCRIPTION
    Downloads the latest stable mpv Windows x86_64 release, installs uosc using
    its official installer, downloads thumbfast and delete_current_file, and
    downloads this script's own mpv.conf, input.conf, uosc.conf, and
    thumbfast.conf from its GitHub repository into portable_config.

    This script does not update an existing installation.
    The target directory must either not exist or be empty.

    Fully self-contained: it can be run directly (.\install.ps1) or piped
    straight from GitHub, e.g.:
        irm https://raw.githubusercontent.com/DevBehnam/mpv-config/main/install.ps1 | iex
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$DefaultInstallPath = Join-Path (Get-Location) 'mpv'

$MpvApiUrl = 'https://api.github.com/repos/mpv-player/mpv/releases/latest'
$UoscInstallerUrl = 'https://raw.githubusercontent.com/tomasklaen/uosc/HEAD/installers/windows.ps1'
$DeleteScriptUrl = 'https://raw.githubusercontent.com/stax76/mpv-scripts/main/delete_current_file.lua'
$ThumbfastScriptUrl = 'https://raw.githubusercontent.com/po5/thumbfast/master/thumbfast.lua'
$KeybindVisualizerScriptUrl = 'https://raw.githubusercontent.com/v-amorim/moonlight-mpv/refs/heads/main/portable_config/scripts/keybind-visualizer.lua'
$KeybindVisualizerJsonUrl = 'https://raw.githubusercontent.com/v-amorim/moonlight-mpv/refs/heads/main/portable_config/script-opts/keybind-visualizer-layouts.json'
$SubSeekScriptURL = 'https://raw.githubusercontent.com/v-amorim/moonlight-mpv/refs/heads/main/portable_config/scripts/sub-seek.lua'
$YtdlAutoFormatScriptURL = 'https://raw.githubusercontent.com/Samillion/mpv-ytdlautoformat/refs/heads/master/ytdlautoformat.lua'
$YtSubScriptUrl = 'https://raw.githubusercontent.com/Idlusen/mpv-ytsub/refs/heads/main/ytsub.lua'

# repository config files
$ConfigRepoRawBase = 'https://raw.githubusercontent.com/DevBehnam/mpv-config/main'
$MpvConfigUrl = "$ConfigRepoRawBase/mpv.conf"
$InputConfigUrl = "$ConfigRepoRawBase/input.conf"
$UoscConfigUrl = "$ConfigRepoRawBase/uosc.conf"
$ThumbfastConfigUrl = "$ConfigRepoRawBase/thumbfast.conf"
$KeybindVisualizerConfigUrl = "$ConfigRepoRawBase/keybind-visualizer.conf"
$YtdlAutoFormatConfigURL = "$ConfigRepoRawBase/ytdlautoformat.conf"
$YtSubConfigUrl = "$ConfigRepoRawBase/ytsub.conf"


$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'


# ------------------------------------------------------------------------
# Console output helpers
# ------------------------------------------------------------------------

function Write-Header
{
    param([string]$Text)

    Write-Host ''
    Write-Host ('=' * 60)
    Write-Host "  $Text"
    Write-Host ('=' * 60)
    Write-Host ''
}

function Write-Step
{
    param([string]$Text)

    Write-Host ''
    Write-Host "[$Text]" -ForegroundColor Cyan
}

function Write-Result
{
    param(
        [string]$Text,
        [ValidateSet('Success', 'Info', 'Warning')]
        [string]$Type = 'Success'
    )

    $label = switch ($Type)
    {
        'Success'
        { 'OK'
        }
        'Info'
        { 'i.'
        }
        'Warning'
        { 'WARN'
        }
    }

    $color = switch ($Type)
    {
        'Success'
        { 'Green'
        }
        'Info'
        { 'Gray'
        }
        'Warning'
        { 'Yellow'
        }
    }

    Write-Host "  " -NoNewline
    Write-Host $label -ForegroundColor $color -NoNewline
    Write-Host "  $Text"
}

function Write-Failure
{
    param([string]$Text)

    Write-Host "  " -NoNewline
    Write-Host 'ERROR' -ForegroundColor Red -NoNewline
    Write-Host " $Text"
}


# ------------------------------------------------------------------------
# In-place progress bar (bar + percent + size + speed)
# ------------------------------------------------------------------------

function Format-ByteSize
{
    param([double]$Bytes)

    if ($Bytes -ge 1GB)
    { return "{0:N2} GB" -f ($Bytes / 1GB)
    }
    if ($Bytes -ge 1MB)
    { return "{0:N2} MB" -f ($Bytes / 1MB)
    }
    if ($Bytes -ge 1KB)
    { return "{0:N1} KB" -f ($Bytes / 1KB)
    }
    return "$([math]::Round($Bytes)) B"
}

function Write-InlineProgress
{
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [long]$Current,

        [long]$Total = 0,
        [double]$BytesPerSecond = 0,
        [int]$Width = 28
    )

    $fraction = 0.0
    if ($Total -gt 0)
    {
        $fraction = [math]::Min(1.0, $Current / $Total)
    }

    $filled = [int][math]::Floor($fraction * $Width)
    if ($filled -gt $Width)
    { $filled = $Width
    }
    $bar = ('#' * $filled).PadRight($Width, ' ')

    $speedText = if ($BytesPerSecond -gt 0)
    { "$(Format-ByteSize $BytesPerSecond)/s"
    } else
    { '--/s'
    }

    if ($Total -gt 0)
    {
        $percentText = "{0,3:N0}%" -f ($fraction * 100)
        $sizeText = "$(Format-ByteSize $Current) / $(Format-ByteSize $Total)"
        $line = "  $Label [$bar] $percentText  $sizeText  $speedText"
    } else
    {
        $line = "  $Label [$bar]  $(Format-ByteSize $Current)  $speedText"
    }

    Write-Host "`r$($line.PadRight(100))" -NoNewline
}

function Complete-InlineProgress
{
    Write-Host ''
}


# ------------------------------------------------------------------------
# Retry helpers.
# ------------------------------------------------------------------------

function Invoke-WithRetry
{
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 3,
        [string]$DisplayName = 'operation'
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++)
    {
        try
        {
            return & $Action
        } catch
        {
            if ($attempt -ge $MaxAttempts)
            {
                throw
            }

            Write-Result "$DisplayName failed ($($_.Exception.Message)), retrying in $DelaySeconds s..." -Type Warning
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Remove-ItemRobust
{
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Recurse,
        [int]$MaxAttempts = 6
    )

    if (-not (Test-Path -LiteralPath $Path))
    {
        return
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++)
    {
        try
        {
            Remove-Item -LiteralPath $Path -Recurse:$Recurse -Force -ErrorAction Stop
            return
        } catch
        {
            if ($attempt -eq $MaxAttempts)
            {
                Write-Result "Could not remove temporary file(s): $Path (still in use, likely by antivirus). You can delete it manually later." -Type Warning
                return
            }

            Start-Sleep -Milliseconds (300 * $attempt)
        }
    }
}


# ------------------------------------------------------------------------
# Install path handling
# ------------------------------------------------------------------------

function Get-InstallPath
{
    Write-Host "Installation directory" -ForegroundColor White
    Write-Host "Press Enter to use the default (current directory):"
    Write-Host "  $DefaultInstallPath" -ForegroundColor DarkGray
    Write-Host ''

    $inputPath = Read-Host 'Path'

    if ([string]::IsNullOrWhiteSpace($inputPath))
    {
        return $DefaultInstallPath
    }

    return [Environment]::ExpandEnvironmentVariables($inputPath.Trim().Trim('"'))
}

function Confirm-InstallPath
{
    param([string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf)
    {
        throw "The installation path points to a file: $Path"
    }

    if (-not (Test-Path -LiteralPath $Path))
    {
        return
    }

    $children = @(Get-ChildItem -LiteralPath $Path -Force)

    if ($children.Count -gt 0)
    {
        throw "The installation directory already exists and is not empty. This installer does not update existing installations: $Path"
    }
}


# ------------------------------------------------------------------------
# Downloading
# ------------------------------------------------------------------------

function Invoke-Download
{
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Destination,

        [string]$DisplayName = 'Downloading',
        [int]$MaxAttempts = 5,
        [int]$StallTimeoutSeconds = 30
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++)
    {
        try
        {
            Invoke-DownloadAttempt `
                -Uri $Uri `
                -Destination $Destination `
                -DisplayName $DisplayName `
                -StallTimeoutSeconds $StallTimeoutSeconds
            return
        } catch
        {
            Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue

            if ($attempt -ge $MaxAttempts)
            {
                throw "Failed to download $DisplayName after $MaxAttempts attempts: $($_.Exception.Message)"
            }

            $delaySeconds = [math]::Min(20, [math]::Pow(2, $attempt))
            Write-Host ''
            Write-Result "$DisplayName was interrupted, retrying in $delaySeconds s (attempt $attempt of $MaxAttempts)..." -Type Warning
            Start-Sleep -Seconds $delaySeconds
        }
    }
}

function Invoke-DownloadAttempt
{
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Destination,

        [string]$DisplayName,
        [int]$StallTimeoutSeconds
    )

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
    $client.DefaultRequestHeaders.UserAgent.ParseAdd($UserAgent)

    $cts = [System.Threading.CancellationTokenSource]::new()

    try
    {
        # Give the initial request (headers) a bounded amount of time; the
        # per-chunk stall timeout below takes over once the body starts.
        $cts.CancelAfter([TimeSpan]::FromSeconds($StallTimeoutSeconds))

        $response = $client.GetAsync(
            $Uri,
            [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead,
            $cts.Token
        ).GetAwaiter().GetResult()

        $response.EnsureSuccessStatusCode() | Out-Null

        $total = $response.Content.Headers.ContentLength
        if ($null -eq $total)
        { $total = 0
        }

        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $fileStream = [System.IO.File]::Create($Destination)

        try
        {
            $buffer = [byte[]]::new(256KB)
            $downloaded = 0L

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $lastSampleSeconds = 0.0
            $lastSampleBytes = 0L
            $lastDrawSeconds = -1.0
            $speed = 0.0

            Write-InlineProgress -Label $DisplayName -Current 0 -Total $total -BytesPerSecond 0

            while ($true)
            {
                # Reset the sliding stall timer on every read; this only
                # fires if no data at all arrives within the window, not
                # because the overall download is merely slow.
                $cts.CancelAfter([TimeSpan]::FromSeconds($StallTimeoutSeconds))

                $read = $stream.ReadAsync($buffer, 0, $buffer.Length, $cts.Token).GetAwaiter().GetResult()

                if ($read -le 0)
                { break
                }

                $fileStream.Write($buffer, 0, $read)
                $downloaded += $read

                $elapsed = $stopwatch.Elapsed.TotalSeconds

                if (($elapsed - $lastSampleSeconds) -ge 0.5)
                {
                    $speed = ($downloaded - $lastSampleBytes) / [math]::Max(0.001, ($elapsed - $lastSampleSeconds))
                    $lastSampleSeconds = $elapsed
                    $lastSampleBytes = $downloaded
                }

                if (($elapsed - $lastDrawSeconds) -ge 0.1)
                {
                    Write-InlineProgress -Label $DisplayName -Current $downloaded -Total $total -BytesPerSecond $speed
                    $lastDrawSeconds = $elapsed
                }
            }

            $finalTotal = [math]::Max($total, $downloaded)
            Write-InlineProgress -Label $DisplayName -Current $downloaded -Total $finalTotal -BytesPerSecond $speed
            Complete-InlineProgress
        } finally
        {
            $fileStream.Dispose()
            $stream.Dispose()
            $response.Dispose()
        }
    } finally
    {
        $cts.Dispose()
        $client.Dispose()
        $handler.Dispose()
    }
}

# ------------------------------------------------------------------------
# mpv release resolution and installation
# ------------------------------------------------------------------------

function Get-LatestMpvRelease
{
    Write-Host '  Checking latest mpv release...' -ForegroundColor Gray

    $response = Invoke-WithRetry -DisplayName 'Checking mpv release' -Action {
        Invoke-RestMethod -Uri $MpvApiUrl -Headers @{ 'User-Agent' = $UserAgent }
    }

    $version = $response.tag_name

    if ($version -notmatch '^v\d+\.\d+\.\d+$')
    {
        throw "Unexpected mpv release tag: $version"
    }

    $assetName = "mpv-$version-x86_64-pc-windows-msvc.zip"
    $asset = @($response.assets | Where-Object { $_.name -eq $assetName })[0]

    if ($null -eq $asset)
    {
        throw "Could not find the expected Windows asset '$assetName'."
    }

    return [PSCustomObject]@{
        Version   = $version
        AssetName = $assetName
        Url       = $asset.browser_download_url
    }
}

function Expand-MpvArchive
{
    param(
        [string]$ArchivePath,
        [string]$Destination
    )

    $tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "mpv-install-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $tempDirectory -Force | Out-Null

    try
    {
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $tempDirectory -Force

        # Current MSVC releases put the mpv files at the archive root.
        # This also handles a single top-level directory defensively.
        $entries = @(Get-ChildItem -LiteralPath $tempDirectory -Force)

        if ($entries.Count -eq 1 -and $entries[0].PSIsContainer)
        {
            $sourceRoot = $entries[0].FullName
        } else
        {
            $sourceRoot = $tempDirectory
        }

        $files = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File)
        $totalFiles = $files.Count
        $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
        if (-not $totalBytes)
        { $totalBytes = 0
        }

        $copiedBytes = 0L
        $copiedFiles = 0
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $lastDrawSeconds = -1.0

        foreach ($file in $files)
        {
            $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
            $destinationPath = Join-Path $Destination $relative
            $destinationDirectory = Split-Path -Parent $destinationPath

            if (-not (Test-Path -LiteralPath $destinationDirectory))
            {
                New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
            }

            [System.IO.File]::Copy($file.FullName, $destinationPath, $true)

            $copiedBytes += $file.Length
            $copiedFiles++

            $elapsed = $stopwatch.Elapsed.TotalSeconds
            $isLast = $copiedFiles -eq $totalFiles

            if (($elapsed - $lastDrawSeconds) -ge 0.1 -or $isLast)
            {
                $speed = if ($elapsed -gt 0)
                { $copiedBytes / $elapsed
                } else
                { 0
                }
                Write-InlineProgress -Label "Installing mpv ($copiedFiles/$totalFiles files)" -Current $copiedBytes -Total $totalBytes -BytesPerSecond $speed
                $lastDrawSeconds = $elapsed
            }
        }

        Complete-InlineProgress
    } finally
    {
        Remove-ItemRobust -Path $tempDirectory -Recurse
    }
}

function Invoke-UoscInstaller
{
    param([string]$InstallDirectory)

    # The official installer detects portable_config when run from an mpv
    # installation directory. Run it in a separate PowerShell process so its
    # Exit 1 on failure cannot terminate this installer itself.
    $installerPath = Join-Path $env:TEMP "uosc-installer-$([guid]::NewGuid()).ps1"

    try
    {
        Invoke-Download `
            -Uri $UoscInstallerUrl `
            -Destination $installerPath `
            -DisplayName 'Downloading uosc installer'

        Push-Location -LiteralPath $InstallDirectory

        try
        {
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $installerPath

            if ($LASTEXITCODE -ne 0)
            {
                throw "The official uosc installer exited with code $LASTEXITCODE."
            }
        } finally
        {
            Pop-Location
        }
    } finally
    {
        Remove-ItemRobust -Path $installerPath
    }
}



# ------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------

try
{
    Write-Header 'MPV CONFIG INSTALLER'

    Write-Host 'This installer creates a new portable mpv installation.'
    Write-Host 'It will not update or modify an existing non-empty installation.'
    Write-Host ''

    $InstallDirectory = Get-InstallPath
    $InstallDirectory = [System.IO.Path]::GetFullPath($InstallDirectory)

    Write-Host ''
    Write-Host "Install path:" -ForegroundColor DarkGray
    Write-Host "  $InstallDirectory" -ForegroundColor White

    Confirm-InstallPath -Path $InstallDirectory

    Write-Step 'Preparing installation directory'

    if (-not (Test-Path -LiteralPath $InstallDirectory))
    {
        New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
        Write-Result "Created $InstallDirectory"
    } else
    {
        Write-Result 'Installation directory already exists and is empty.'
    }

    $PortableConfig = Join-Path $InstallDirectory 'portable_config'
    New-Item -ItemType Directory -Path $PortableConfig -Force | Out-Null

    Write-Result 'Created portable_config'

    Write-Step 'Downloading mpv'

    $mpvRelease = Get-LatestMpvRelease

    Write-Host "  Version: $($mpvRelease.Version)" -ForegroundColor Gray
    Write-Host "  Asset:   $($mpvRelease.AssetName)" -ForegroundColor Gray
    Write-Host ''

    $mpvArchive = Join-Path $env:TEMP $mpvRelease.AssetName

    Invoke-Download `
        -Uri $mpvRelease.Url `
        -Destination $mpvArchive `
        -DisplayName "mpv $($mpvRelease.Version)"

    Write-Result "Downloaded mpv $($mpvRelease.Version)"

    Write-Step 'Installing mpv'

    Expand-MpvArchive `
        -ArchivePath $mpvArchive `
        -Destination $InstallDirectory

    Write-Result 'Installed mpv'

    Remove-ItemRobust -Path $mpvArchive

    Write-Step 'Installing uosc'

    Invoke-UoscInstaller -InstallDirectory $InstallDirectory
    Write-Result 'Installed uosc using the official installer'

    $ScriptsDirectory = Join-Path $PortableConfig 'scripts'
    $ScriptOptsDirectory = Join-Path $PortableConfig 'script-opts'

    New-Item -ItemType Directory -Path $ScriptsDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $ScriptOptsDirectory -Force | Out-Null

    Write-Step 'Installing third-party scripts'

    $deleteScript = Join-Path $ScriptsDirectory 'delete_current_file.lua'
    Invoke-Download `
        -Uri $DeleteScriptUrl `
        -Destination $deleteScript `
        -DisplayName 'delete_current_file.lua'
    Write-Result 'Installed delete_current_file.lua'

    $thumbfastScript = Join-Path $ScriptsDirectory 'thumbfast.lua'
    Invoke-Download `
        -Uri $ThumbfastScriptUrl `
        -Destination $thumbfastScript `
        -DisplayName 'thumbfast.lua'
    Write-Result 'Installed thumbfast.lua'

    $keybindVisualizerScript = Join-Path $ScriptsDirectory 'keybind-visualizer.lua'
    Invoke-Download `
        -Uri $KeybindVisualizerScriptUrl `
        -Destination $keybindVisualizerScript `
        -DisplayName 'keybind-visualizer.lua'
    Write-Result 'Installed keybind-visualizer.lua'

    $SubSeekScript = Join-Path $ScriptsDirectory 'sub-seek.lua'
    Invoke-Download `
        -Uri $SubSeekScriptURL `
        -Destination $SubSeekScript `
        -DisplayName 'sub-seek.lua'
    Write-Result 'Installed sub-seek.lua'

    $YtdlAutoFormatScript = Join-Path $ScriptsDirectory 'ytdlautoformat.lua'
    Invoke-Download `
        -Uri $YtdlAutoFormatScriptURL `
        -Destination $YtdlAutoFormatScript `
        -DisplayName 'ytdlautoformat.lua'
    Write-Result 'Installed ytdlautoformat.lua'

    $YtSubScript = Join-Path $ScriptsDirectory 'ytsub.lua'
    Invoke-Download `
        -Uri $YtSubScriptUrl `
        -Destination $YtSubScript `
        -DisplayName 'ytsub.lua'
    Write-Result 'Installed ytsub.lua'

    Write-Step 'Installing configuration'

    Invoke-Download `
        -Uri $MpvConfigUrl `
        -Destination (Join-Path $PortableConfig 'mpv.conf') `
        -DisplayName 'mpv.conf'
    Write-Result 'Installed mpv.conf'

    Invoke-Download `
        -Uri $InputConfigUrl `
        -Destination (Join-Path $PortableConfig 'input.conf') `
        -DisplayName 'input.conf'
    Write-Result 'Installed input.conf'

    Invoke-Download `
        -Uri $UoscConfigUrl `
        -Destination (Join-Path $ScriptOptsDirectory 'uosc.conf') `
        -DisplayName 'uosc.conf'
    Write-Result 'Installed uosc.conf'

    Invoke-Download `
        -Uri $ThumbfastConfigUrl `
        -Destination (Join-Path $ScriptOptsDirectory 'thumbfast.conf') `
        -DisplayName 'thumbfast.conf'
    Write-Result 'Installed thumbfast.conf'

    $keybindVisualizerConfig = Join-Path $ScriptOptsDirectory 'keybind-visualizer.conf'
    Invoke-Download `
        -Uri $KeybindVisualizerConfigUrl `
        -Destination $keybindVisualizerConfig `
        -DisplayName 'keybind-visualizer.conf'
    Write-Result 'Installed keybind-visualizer.conf'

    $keybindVisualizerJson = Join-Path $ScriptOptsDirectory 'keybind-visualizer-layouts.json'
    Invoke-Download `
        -Uri $KeybindVisualizerJsonUrl `
        -Destination $keybindVisualizerJson `
        -DisplayName 'keybind-visualizer-layouts.json'
    Write-Result 'Installed keybind-visualizer-layouts.json'

    $YtdlAutoFormatConfig = Join-Path $ScriptOptsDirectory 'ytdlautoformat.conf'
    Invoke-Download `
        -Uri $YtdlAutoFormatConfigURL `
        -Destination $YtdlAutoFormatConfig `
        -DisplayName 'ytdlautoformat.conf'
    Write-Result 'Installed ytdlautoformat.conf'

    $YtSubConfig = Join-Path $ScriptOptsDirectory 'ytsub.conf'
    Invoke-Download `
        -Uri $YtSubConfigUrl `
        -Destination $YtSubConfig `
        -DisplayName 'ytsub.conf'
    Write-Result 'Installed ytsub.conf'

    Write-Header 'INSTALLATION COMPLETE'

    Write-Host 'Installed to:' -ForegroundColor White
    Write-Host "  $InstallDirectory" -ForegroundColor Green
    Write-Host ''
    Write-Host 'Launch:' -ForegroundColor White
    Write-Host "  $([System.IO.Path]::Combine($InstallDirectory, 'mpv.exe'))" -ForegroundColor Gray
    Write-Host ''
    Write-Host "mpv       $($mpvRelease.Version)" -ForegroundColor Gray
    Write-Host 'uosc      installed' -ForegroundColor Gray
    Write-Host 'thumbfast installed' -ForegroundColor Gray
    Write-Host 'config    installed' -ForegroundColor Gray
    Write-Host ''
} catch
{
    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor Red
    Write-Host '  INSTALLATION FAILED' -ForegroundColor Red
    Write-Host ('=' * 60) -ForegroundColor Red
    Write-Host ''
    Write-Failure $_.Exception.Message
    Write-Host ''
    Write-Host 'No automatic cleanup was performed so you can inspect the installation directory.' -ForegroundColor Yellow
    Write-Host ''
}
