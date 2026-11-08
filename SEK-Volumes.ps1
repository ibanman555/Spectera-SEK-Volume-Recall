# Spectera SEK Volume Presets 1.0 - shareable release (all paired SEK packs)
# Uses Sennheiser Spectera SSCv2 /api/mts/paired/all (not live connected-only devices).
# Windows PowerShell 5.1+ with Windows curl.exe; for a trusted control LAN.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Setup','Export','Preview','Apply','List')]
    [string]$Mode,
    [string]$BaseIP = '',
    [switch]$TrustLocalCertificate
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$CredentialPath = Join-Path $Root 'spectera-password.dat'
$BaseIPPath = Join-Path $Root 'spectera-base-ip.txt'
$PresetPath = Join-Path $Root 'sek-volume-presets.csv'
# For List/Export/Preview/Apply, use the saved IP from Setup unless -BaseIP overrides it.
if ($Mode -ne 'Setup') {
    if ([string]::IsNullOrWhiteSpace($BaseIP)) {
        if (-not (Test-Path -LiteralPath $BaseIPPath)) {
            throw "No saved base-station IP. Run this script with -Mode Setup first."
        }
        $BaseIP = (Get-Content -LiteralPath $BaseIPPath -TotalCount 1).Trim()
    }
    $parsedAddress = $null
    if (-not [Net.IPAddress]::TryParse($BaseIP, [ref]$parsedAddress) -or
        $parsedAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Invalid base-station IPv4 address: $BaseIP"
    }
    $BaseUrl = "https://${BaseIP}:443"
}
$script:CurlExecutable = $null
$script:OwnUsageMark = $false
$script:UsageMarkName = '3rd-party.SEK-Volume-Presets'
# Every silent Apply run writes a dated diagnostic transcript.
$script:TranscriptActive = $false
if ($Mode -eq 'Apply') {
    $LogDirectory = Join-Path $Root 'Logs'
    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
    $LogPath = Join-Path $LogDirectory ("SEK-Recall-{0}.log" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff'))
    Start-Transcript -LiteralPath $LogPath -ErrorAction Stop | Out-Null
    $script:TranscriptActive = $true
    Write-Host "Spectera SEK recall started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "Log: $LogPath"
}

function Get-PasswordPlaintext {
    if (-not (Test-Path -LiteralPath $CredentialPath)) {
        throw "No saved credentials. Run this script once with -Mode Setup."
    }
    $secure = (Get-Content -LiteralPath $CredentialPath -Raw).Trim() | ConvertTo-SecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

# Use native Windows curl.exe for compatibility with the Spectera base station's
# HTTPS stack. This matches the tested command:
# curl.exe -k --http1.1 --noproxy "*" -u controlSennheiser https://.../api/mts/paired/all
# The credential is passed via curl's redirected standard INPUT (not on the
# process command line, not in a temporary plaintext file).
function Open-ApiClient {
    $cmd = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        throw 'curl.exe was not found. Windows 10/11 should include curl.exe.'
    }
    $script:CurlExecutable = $cmd.Source
    if (-not (Test-Path -LiteralPath $CredentialPath)) {
        throw "No saved credentials. Run this script once with -Mode Setup. Missing: $CredentialPath"
    }
}

# A curl --config line uses quoted strings, and backslashes/double-quotes
# must be escaped. This is used for URLs and JSON request bodies only.
function Quote-CurlConfigValue {
    param([AllowEmptyString()][string]$Value)
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n')
    return '"' + $escaped + '"'
}

function Invoke-SpecteraApi {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('GET','PUT')][string]$Method,
        [Parameter(Mandatory=$true)][string]$Path,
        [object]$Body = $null
    )
    if ($null -eq $script:CurlExecutable) { throw 'curl.exe transport has not been initialized.' }
    if ($Path -notmatch '^/api/[A-Za-z0-9/_-]+$') { throw "Invalid API path: $Path" }

    $raw = Get-PasswordPlaintext
    try {
        # Basic authorization is transported through redirected stdin, never argv.
        $authToken = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("controlSennheiser:$raw"))
    }
    finally { $raw = $null }

    $lines = @(
        'silent'
        'show-error'
        'http1.1'
        'noproxy = "*"'
        'connect-timeout = 5'
        'max-time = 20'
        ('request = ' + (Quote-CurlConfigValue $Method))
        ('url = ' + (Quote-CurlConfigValue "$BaseUrl$Path"))
        ('header = ' + (Quote-CurlConfigValue "Authorization: Basic $authToken"))
        'write-out = "SPECTERA_HTTP_STATUS:%{http_code}"'
    )
    $authToken = $null
    if ($TrustLocalCertificate) { $lines += 'insecure' }
    if ($null -ne $Body) {
        $json = ConvertTo-Json -InputObject $Body -Depth 8 -Compress
        $lines += 'header = "Content-Type: application/json"'
        $lines += 'data-raw = ' + (Quote-CurlConfigValue $json)
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $script:CurlExecutable
    # -q disables default ~/.curlrc. Config is supplied on stdin only.
    $startInfo.Arguments = '-q --config -'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
    $startInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
    # Windows PowerShell 5.1 runs on .NET Framework; ProcessStartInfo has no StandardInputEncoding property.
    # curl configuration and auth headers are ASCII; stdin default encoding is sufficient.

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Could not start curl.exe.' }
        $process.StandardInput.WriteLine(($lines -join "`n"))
        $process.StandardInput.Close()
        # Output is JSON (typically tens of KB); errors are short due to -sS.
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($stdout -notmatch 'SPECTERA_HTTP_STATUS:(\d{3})\s*$') {
            throw "Spectera $Method ${Path}: curl exit $($process.ExitCode). $stderr"
        }
        $status = [int]$Matches[1]
        $responseBody = $stdout -replace 'SPECTERA_HTTP_STATUS:\d{3}\s*$', ''
        if ($process.ExitCode -ne 0) {
            throw "Spectera $Method ${Path}: curl exit $($process.ExitCode), HTTP $status. $stderr"
        }
        if ($status -lt 200 -or $status -ge 300) {
            throw "Spectera $Method ${Path}: HTTP $status. $responseBody"
        }
        if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
            try { return (ConvertFrom-Json -InputObject $responseBody) }
            catch {
                # Some valid PUT responses contain an empty body or other
                # non-JSON content. For GET, bad JSON must still be reported.
                if ($Method -eq 'GET') { throw "Invalid JSON from Spectera $Path. $($_.Exception.Message)" }
            }
        }
    }
    finally { $process.Dispose() }
}

function Get-PairedSek {
    $devices = @(Invoke-SpecteraApi -Method GET -Path '/api/mts/paired/all')
    return @($devices | Where-Object { $_.type -eq 'SEK' } | Sort-Object mtUid)
}

function Enter-UsageMark {
    $mark = Invoke-SpecteraApi -Method GET -Path '/api/ssc/usagemark'
    if (-not [string]::IsNullOrWhiteSpace([string]$mark.usedBy) -and $mark.usedBy -ne $script:UsageMarkName) {
        throw "Another application is writing to Spectera: $($mark.usedBy). Retry after it finishes."
    }
    Invoke-SpecteraApi -Method PUT -Path '/api/ssc/usagemark' -Body @{ usedBy=$script:UsageMarkName; timer=60 } | Out-Null
    $script:OwnUsageMark = $true
}

function Renew-UsageMark {
    Invoke-SpecteraApi -Method PUT -Path '/api/ssc/usagemark' -Body @{ usedBy=$script:UsageMarkName; timer=60 } | Out-Null
}

function Exit-UsageMark {
    if ($script:OwnUsageMark -and $null -ne $script:CurlExecutable) {
        try {
            Invoke-SpecteraApi -Method PUT -Path '/api/ssc/usagemark' -Body @{ usedBy=''; timer=5 } | Out-Null
        }
        catch { Write-Warning "Could not release usage mark; it will time out: $($_.Exception.Message)" }
        $script:OwnUsageMark = $false
    }
}

function Read-VolumePresets {
    if (-not (Test-Path -LiteralPath $PresetPath)) {
        throw "Preset file not found: $PresetPath . Run -Mode Export first."
    }
    $items = @(Import-Csv -LiteralPath $PresetPath)
    # Safety: reject an empty CSV. Before writing, validate that every paired SEK UID is represented.
    if ($items.Count -lt 1) {
        throw "CSV has no SEK entries. No settings changed."
    }
    $seen = @{}
    $parsed = @()
    foreach ($item in $items) {
        [long]$id = 0
        [double]$vol = 0
        if (-not [long]::TryParse([string]$item.mtUid, [ref]$id) -or $id -lt 0 -or $id -gt 4294967295) {
            throw "Invalid mtUid in preset file: $($item.mtUid)"
        }
        if ($seen.ContainsKey([string]$id)) { throw "Duplicate mtUid in preset file: $id" }
        $seen[[string]$id] = $true
        if (-not [double]::TryParse([string]$item.VolumeDb, [System.Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$vol)) {
            throw "Invalid VolumeDb for SEK $id (use e.g. -35.5): $($item.VolumeDb)"
        }
        if ($vol -lt -100 -or $vol -gt 27.5 -or [Math]::Abs($vol*2 - [Math]::Round($vol*2)) -gt 0.00001) {
            throw "Invalid VolumeDb $vol for SEK $id (supported global range -100 to +27.5 dB, in 0.5 dB increments)."
        }
        $parsed += [pscustomobject]@{
            mtUid=$id; Name=[string]$item.Name; Serial=[string]$item.Serial; VolumeDb=$vol
        }
    }
    return $parsed
}

try {
    if ($Mode -eq 'Setup') {
        $enteredIP = $BaseIP
        if ([string]::IsNullOrWhiteSpace($enteredIP)) {
            $enteredIP = Read-Host 'Spectera base station IPv4 address (e.g. 192.168.1.100)'
        }
        $enteredIP = ([string]$enteredIP).Trim()
        $parsedAddress = $null
        if (-not [Net.IPAddress]::TryParse($enteredIP, [ref]$parsedAddress) -or
            $parsedAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
            throw "Invalid IPv4 address: $enteredIP"
        }
        $password = Read-Host 'Enter your Spectera WebUI/base-station password' -AsSecureString
        if ($null -eq $password -or $password.Length -eq 0) { throw 'Empty password was not saved.' }
        $enteredIP | Set-Content -LiteralPath $BaseIPPath -Encoding ASCII
        $password | ConvertFrom-SecureString | Set-Content -LiteralPath $CredentialPath -Encoding ASCII
        Write-Host "Base station IP saved: $enteredIP"
        Write-Host "Encrypted password saved for the current Windows user: $CredentialPath"
        Write-Host 'Only the same Windows user on this same computer can decrypt this credential.'
        return
    }

    Open-ApiClient
    if ($Mode -eq 'List') {
        $devices = Get-PairedSek
        $devices | Select-Object name, serial, mtUid, state, headphoneVolume, headphoneVolumeMin, headphoneVolumeMax | Format-Table -AutoSize
        Write-Host "Found $($devices.Count) paired SEK entries (including powered-off packs)."
        return
    }
    if ($Mode -eq 'Export') {
        if (Test-Path -LiteralPath $PresetPath) {
            throw "Preset already exists: $PresetPath . Rename or back it up first so you don't overwrite desired values."
        }
        $devices = Get-PairedSek
        if ($devices.Count -lt 1) { throw "No paired SEK entries were returned. No CSV exported." }
        $devices | ForEach-Object {
            [pscustomobject]@{
                mtUid=[string]$_.mtUid
                Name=[string]$_.name
                Serial=[string]$_.serial
                VolumeDb=([double]$_.headphoneVolume).ToString('0.0', [Globalization.CultureInfo]::InvariantCulture)
            }
        } | Export-Csv -LiteralPath $PresetPath -NoTypeInformation -Encoding UTF8
        Write-Host "Exported $($devices.Count) paired SEK records to: $PresetPath"
        Write-Host 'Keep ALL paired SEK rows. Edit only VolumeDb values; do not change mtUid.'
        Write-Host 'Preview and Apply validate that the CSV includes every paired SEK before writing.'
        return
    }

    $presets = @(Read-VolumePresets)
    $devices = @(Get-PairedSek)
    if ($devices.Count -lt 1) {
        throw "No paired SEK entries were returned. No settings changed."
    }
    if ($presets.Count -ne $devices.Count) {
        throw "CSV contains $($presets.Count) SEK entries, but base station has $($devices.Count) paired SEK entries. Include ALL paired SEK entries before applying. No settings changed."
    }
    $lookup = @{}
    foreach ($d in $devices) { $lookup[[string]$d.mtUid] = $d }
    foreach ($p in $presets) {
        if (-not $lookup.ContainsKey([string]$p.mtUid)) {
            throw "Preset SEK $($p.mtUid) ($($p.Name)) is not paired to this base station. No settings changed."
        }
        $device = $lookup[[string]$p.mtUid]
        if ($null -ne $device.headphoneVolumeMin -and $p.VolumeDb -lt [double]$device.headphoneVolumeMin) {
            throw "Volume $($p.VolumeDb) dB is below configured minimum for SEK $($p.mtUid). No settings changed."
        }
        if ($null -ne $device.headphoneVolumeMax -and $p.VolumeDb -gt [double]$device.headphoneVolumeMax) {
            throw "Volume $($p.VolumeDb) dB is above configured maximum for SEK $($p.mtUid). No settings changed."
        }
    }
    # Count equality, duplicate checks, and lookup verification ensure that the CSV covers ALL paired SEK UIDs.

    Write-Host "Base station: $BaseIP    Preset SEK entries: $($presets.Count)    Paired total: $($devices.Count)"
    Write-Host 'All paired SEK packs are included, regardless of connection state.'
    $report = @(
        foreach ($p in $presets) {
            $d = $lookup[[string]$p.mtUid]
            [pscustomobject]@{
                Name=$p.Name; Serial=$p.Serial; mtUid=$p.mtUid
                StoredDb=[double]$d.headphoneVolume; TargetDb=[double]$p.VolumeDb
                Change=if ([double]$d.headphoneVolume -eq [double]$p.VolumeDb) { 'Same' } else { 'Change' }
            }
        }
    )
    $report | Format-Table -AutoSize

    if ($Mode -eq 'Preview') {
        Write-Host 'PREVIEW ONLY: No changes were sent.'
        return
    }

    # No pack has to be connected; write the saved pairing records on the base station.
    Enter-UsageMark
    $failed = @()
    foreach ($p in $presets) {
        $old = $lookup[[string]$p.mtUid]
        if ([double]$old.headphoneVolume -eq [double]$p.VolumeDb) {
            Write-Host "UNCHANGED  $($p.Name) ($($p.mtUid))  $($p.VolumeDb) dB"
            continue
        }
        try {
            Renew-UsageMark
            $body = @{ mtUid=[long]$p.mtUid; type='SEK'; headphoneVolume=[double]$p.VolumeDb }
            Invoke-SpecteraApi -Method PUT -Path "/api/mts/paired/all/$($p.mtUid)" -Body $body | Out-Null
            $check = Invoke-SpecteraApi -Method GET -Path "/api/mts/paired/all/$($p.mtUid)"
            if ([double]$check.headphoneVolume -ne [double]$p.VolumeDb) {
                throw "Readback returned $($check.headphoneVolume) dB instead of $($p.VolumeDb) dB"
            }
            Write-Host "APPLIED    $($p.Name) ($($p.mtUid))  $($p.VolumeDb) dB"
        }
        catch {
            $failed += $p.mtUid
            Write-Warning "FAILED SEK $($p.mtUid): $($_.Exception.Message)"
        }
    }
    if ($failed.Count -gt 0) { throw "$($failed.Count) SEK stored-volume updates failed: $($failed -join ', ')" }
    Write-Host "Finished: all $($presets.Count) paired SEK entries show their intended stored volume."
}
catch {
    Write-Error ('Spectera operation failed: ' + $_.Exception.Message)
    exit 1
}
finally {
    Exit-UsageMark
    if ($script:TranscriptActive) {
        try { Stop-Transcript | Out-Null }
        catch { }
    }
}