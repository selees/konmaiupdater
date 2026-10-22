# ScriptVersion: 1.2.0
param (
    [string]$ConfigFile = "$PSScriptRoot\config.ini"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$host.UI.RawUI.WindowTitle = "KONMAI Game Auto Updater"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "              KONMAI Game Auto Updater                    " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# Helper: Ensure config.ini exists and non-destructively append any missing options
function Ensure-ConfigIni ($configPath) {
    if (-not (Test-Path $configPath)) {
        @"
[Server]
; Web server URL (e.g. http://192.168.0.10:8080)
ServerUrl=http://localhost:8080

[Update]
; Game ID code to match patches (e.g. KFC, MDX, LDJ)
GameID=KFC

; Target game directory (. for current directory, or ./KFC for subfolder)
TargetDir=./KFC

[Modules]
; Copy files inside modules folder to its parent folder (true / false)
MoveModulesUp=true
; Path to modules directory (leave empty to auto-detect inside TargetDir)
ModulesDir=./KFC/contents/modules

[Patches]
; Enable automatic DLL patching via sp2xpatcher (true / false)
EnableSp2xPatcher=true
; List of patches to apply (comma-separated).
; Automatically populated from existing patched DLLs before update, or specify manually.
; For memory patches: Patch Name
; For union patches: Patch Name:Option Name
; Example:
; EnabledPatches=Standard/Menu Timer Freeze, Premium Free Timer Freeze, Game FPS Target:120 FPS
EnabledPatches=
"@ | Set-Content -Path $configPath -Encoding UTF8
        Write-Host "[Notice] Created default config.ini" -ForegroundColor Gray
        return
    }

    # Non-destructive check for missing sections/keys in existing config.ini
    $rawLines = @(Get-Content $configPath -Encoding UTF8)
    $existingKeys = @{}
    $existingSections = @{}

    foreach ($line in $rawLines) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith(";") -or $trimmed.StartsWith("#") -or $trimmed -eq "") { continue }
        if ($trimmed -match "^\[([^\]]+)\]$") {
            $existingSections[$matches[1].Trim().ToLower()] = $true
        } elseif ($trimmed -match "^([A-Za-z0-9_]+)\s*=") {
            $existingKeys[$matches[1].Trim().ToLower()] = $true
        }
    }

    $appendedLines = [System.Collections.Generic.List[string]]::new()

    # Check [Server]
    if (-not $existingKeys.ContainsKey("serverurl")) {
        if (-not $existingSections.ContainsKey("server")) {
            $appendedLines.Add("")
            $appendedLines.Add("[Server]")
        }
        $appendedLines.Add("; Web server URL (e.g. http://192.168.0.10:8080)")
        $appendedLines.Add("ServerUrl=http://localhost:8080")
    }

    # Check [Update]
    if (-not $existingKeys.ContainsKey("gameid") -or -not $existingKeys.ContainsKey("targetdir")) {
        if (-not $existingSections.ContainsKey("update")) {
            $appendedLines.Add("")
            $appendedLines.Add("[Update]")
        }
        if (-not $existingKeys.ContainsKey("gameid")) {
            $appendedLines.Add("; Game ID code to match patches (e.g. KFC, MDX, LDJ)")
            $appendedLines.Add("GameID=KFC")
        }
        if (-not $existingKeys.ContainsKey("targetdir")) {
            $appendedLines.Add("; Target game directory (. for current directory, or ./KFC for subfolder)")
            $appendedLines.Add("TargetDir=./KFC")
        }
    }

    # Check [Modules]
    if (-not $existingKeys.ContainsKey("movemodulesup") -or -not $existingKeys.ContainsKey("modulesdir")) {
        if (-not $existingSections.ContainsKey("modules")) {
            $appendedLines.Add("")
            $appendedLines.Add("[Modules]")
        }
        if (-not $existingKeys.ContainsKey("movemodulesup")) {
            $appendedLines.Add("; Copy files inside modules folder to its parent folder (true / false)")
            $appendedLines.Add("MoveModulesUp=true")
        }
        if (-not $existingKeys.ContainsKey("modulesdir")) {
            $appendedLines.Add("; Path to modules directory (leave empty to auto-detect inside TargetDir)")
            $appendedLines.Add("ModulesDir=./KFC/contents/modules")
        }
    }

    # Check [Patches]
    if (-not $existingKeys.ContainsKey("enablesp2xpatcher") -or -not $existingKeys.ContainsKey("enabledpatches")) {
        if (-not $existingSections.ContainsKey("patches")) {
            $appendedLines.Add("")
            $appendedLines.Add("[Patches]")
        }
        if (-not $existingKeys.ContainsKey("enablesp2xpatcher")) {
            $appendedLines.Add("; Enable automatic DLL patching via sp2xpatcher (true / false)")
            $appendedLines.Add("EnableSp2xPatcher=true")
        }
        if (-not $existingKeys.ContainsKey("enabledpatches")) {
            $appendedLines.Add("; List of patches to apply (comma-separated).")
            $appendedLines.Add("; Automatically populated from existing patched DLLs before update, or specify manually.")
            $appendedLines.Add("; For memory patches: Patch Name")
            $appendedLines.Add("; For union patches: Patch Name:Option Name")
            $appendedLines.Add("; Example:")
            $appendedLines.Add("; EnabledPatches=Standard/Menu Timer Freeze, Premium Free Timer Freeze, Game FPS Target:120 FPS")
            $appendedLines.Add("EnabledPatches=")
        }
    }

    if ($appendedLines.Count -gt 0) {
        $finalLines = $rawLines + $appendedLines.ToArray()
        [System.IO.File]::WriteAllLines($configPath, $finalLines, [System.Text.Encoding]::UTF8)
        Write-Host "[Notice] Added newly introduced option(s) to config.ini (existing settings preserved)." -ForegroundColor Cyan
    }
}

# Helper: Update a single key's value in config.ini in-place without losing comments/formatting
function Set-ConfigIniValue ($configPath, $keyName, $newValue) {
    if (-not (Test-Path $configPath)) { return }
    $lines = @(Get-Content $configPath -Encoding UTF8)
    $updated = $false
    $escapedKey = [regex]::Escape($keyName)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if (-not $trimmed.StartsWith(";") -and -not $trimmed.StartsWith("#")) {
            if ($trimmed -match "^$escapedKey\s*=") {
                $lines[$i] = "$keyName=$newValue"
                $updated = $true
                break
            }
        }
    }
    if (-not $updated) {
        $lines += "$keyName=$newValue"
    }
    [System.IO.File]::WriteAllLines($configPath, $lines, [System.Text.Encoding]::UTF8)
}

# 1. Load & Migrate config.ini
$serverUrl = "http://localhost:8080"
$gameId = ""
$targetDir = "$PSScriptRoot"
$moveModulesUp = $false
$modulesDir = ""
$enableSp2xPatcher = $true
$enabledPatchesRaw = ""

# Local temporary directory inside the updater folder
$localTempDir = Join-Path $PSScriptRoot "_temp"
if (-not (Test-Path $localTempDir)) {
    New-Item -ItemType Directory -Path $localTempDir -Force | Out-Null
}

Ensure-ConfigIni -configPath $ConfigFile

if (Test-Path $ConfigFile) {
    Get-Content $ConfigFile -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line.StartsWith(";") -or $line.StartsWith("#")) { return }
        
        if ($line -match "^ServerUrl\s*=\s*(.+)$") {
            $serverUrl = $matches[1].TrimEnd('/')
        }
        elseif ($line -match "^GameID\s*=\s*(.+)$") {
            $gameId = $matches[1].Trim().ToUpper()
        }
        elseif ($line -match "^TargetDir\s*=\s*(.+)$") {
            $val = $matches[1].Trim()
            if ($val -eq ".") {
                $targetDir = $PSScriptRoot
            } else {
                $fullPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $val))
                if (-not (Test-Path $fullPath)) {
                    New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
                }
                $targetDir = $fullPath
            }
        }
        elseif ($line -match "^MoveModulesUp\s*=\s*(.+)$") {
            $moveModulesUp = ($matches[1].Trim().ToLower() -eq "true")
        }
        elseif ($line -match "^ModulesDir\s*=\s*(.+)$") {
            $modulesDir = $matches[1].Trim()
        }
        elseif ($line -match "^EnableSp2xPatcher\s*=\s*(.+)$") {
            $enableSp2xPatcher = ($matches[1].Trim().ToLower() -eq "true")
        }
        elseif ($line -match "^EnabledPatches\s*=\s*(.*)$") {
            $enabledPatchesRaw = $matches[1].Trim()
        }
    }
}

Write-Host "Server URL : $serverUrl" -ForegroundColor White
Write-Host "Game ID    : $(if ($gameId) { $gameId } else { 'ALL' })" -ForegroundColor White
Write-Host "Target Dir : $targetDir" -ForegroundColor White
if ($enableSp2xPatcher) {
    Write-Host "sp2xpatcher: Enabled" -ForegroundColor Green
}

# 2. Query available patches from server
Write-Host "`nChecking for available patches..." -ForegroundColor Yellow

$patchList = @()
$serverReachable = $true
try {
    $listUrl = "$serverUrl/list"
    $response = & curl.exe -s --connect-timeout 5 "$listUrl"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to connect to server (curl exit code: $LASTEXITCODE)"
    }
    if (-not [string]::IsNullOrWhiteSpace($response)) {
        $patchList = @($response -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
    }
} catch {
    $serverReachable = $false
    Write-Host "[WARNING] Could not connect to update server ($serverUrl)." -ForegroundColor Red
    Write-Host "Please ensure the server is running and the IP address in config.ini is correct." -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor DarkGray
}

if ($serverReachable) {
    # Filter by GameID if specified
    if (-not [string]::IsNullOrWhiteSpace($gameId)) {
        $escapedGameId = [regex]::Escape($gameId)
        $patchList = @($patchList | Where-Object { $_ -match "^$escapedGameId-" })
        Write-Host "Filtered $($patchList.Count) patch file(s) matching Game ID [$gameId]." -ForegroundColor Gray
    } else {
        Write-Host "Found $($patchList.Count) patch file(s) on server." -ForegroundColor Gray
    }

    if ($patchList.Count -eq 0) {
        Write-Host "`n[Notice] No matching patch (.rar) files found on server." -ForegroundColor Yellow
    }
}

# 3. Detect current game version from bootstrap.xml (auto-detect in target directory)
$currentVersion = ""
$resolvedBootstrap = ""

$bootstrapCandidates = @(
    (Join-Path $targetDir "contents\prop\bootstrap.xml"),
    (Join-Path $targetDir "prop\bootstrap.xml"),
    (Join-Path $targetDir "bootstrap.xml")
)
foreach ($c in $bootstrapCandidates) {
    if (Test-Path $c -PathType Leaf) {
        $resolvedBootstrap = $c
        break
    }
}
if (-not $resolvedBootstrap) {
    $found = Get-ChildItem -Path $targetDir -Filter "bootstrap.xml" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        $resolvedBootstrap = $found.FullName
    }
}

# Inspect <release_code> from bootstrap.xml if found
if ($resolvedBootstrap -and (Test-Path $resolvedBootstrap -PathType Leaf)) {
    $bContent = Get-Content $resolvedBootstrap -Raw -Encoding UTF8
    if ($bContent -match '(?s)<release_code\b[^>]*>\s*([A-Za-z0-9_-]+)\s*</release_code>') {
        $releaseCode = $matches[1].Trim()
        $currentVersion = if ($gameId) { "$gameId-$releaseCode" } else { $releaseCode }
        Write-Host "`n[Notice] Game version detected from bootstrap.xml: $currentVersion" -ForegroundColor Cyan
    }
}

# Fallback to server lowest patch if bootstrap.xml is missing or empty
if ([string]::IsNullOrWhiteSpace($currentVersion) -and $patchList.Count -gt 0) {
    $validPatches = foreach ($f in $patchList) {
        if ($f -match "^([A-Za-z0-9_]+)-(\d+)\s+to\s+(\d+)\.rar$") {
            [PSCustomObject]@{
                FileName = $f
                GameCode = $matches[1]
                FromVerNum = [long]$matches[2]
                ToVerNum = [long]$matches[3]
                FromFullVer = "$($matches[1])-$($matches[2])"
            }
        }
    }

    if ($validPatches) {
        $sortedPatches = $validPatches | Sort-Object FromVerNum
        $lowestPatch = $sortedPatches[0]
        $currentVersion = $lowestPatch.FromFullVer
        Write-Host "`n[Notice] bootstrap.xml not found." -ForegroundColor Cyan
        Write-Host "  -> Starting sequential update for [$($lowestPatch.GameCode)] from base version: $currentVersion" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] No valid patch naming format found for Game ID [$gameId]." -ForegroundColor Red
        Start-Sleep -Seconds 3
        exit 1
    }
}

if (-not $serverReachable -and [string]::IsNullOrWhiteSpace($currentVersion)) {
    Start-Sleep -Seconds 3
    exit 1
}

if (-not [string]::IsNullOrWhiteSpace($currentVersion)) {
    Write-Host "Current Ver: $currentVersion" -ForegroundColor Green
}
Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray

# Helper functions
function Unpack-Archive ($archivePath, $destPath, $workTempDir) {
    $tempExtract = Join-Path $workTempDir ("unpack_" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null

    $extractSuccess = $false

    # 1. 7-Zip
    $sevenZipCandidates = @(
        (Get-Command 7z -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe",
        "$PSScriptRoot\7za.exe"
    )
    $sevenZip = $sevenZipCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

    if ($sevenZip) {
        & $sevenZip x -y "-o$tempExtract" "$archivePath" | Out-Null
        $extractSuccess = ($LASTEXITCODE -eq 0)
    }

    # 2. WinRAR
    if (-not $extractSuccess) {
        $winRarCandidates = @(
            (Get-Command winrar -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
            "C:\Program Files\WinRAR\WinRAR.exe",
            "C:\Program Files (x86)\WinRAR\WinRAR.exe"
        )
        $winRar = $winRarCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

        if ($winRar) {
            & $winRar x -ibck -y "$archivePath" "$tempExtract\" | Out-Null
            $extractSuccess = ($LASTEXITCODE -eq 0)
        }
    }

    # 3. Windows built-in tar (bsdtar)
    if (-not $extractSuccess -and (Get-Command tar.exe -ErrorAction SilentlyContinue)) {
        tar.exe -xf "$archivePath" -C "$tempExtract"
        $extractSuccess = ($LASTEXITCODE -eq 0)
    }

    if (-not $extractSuccess) {
        Write-Host "[ERROR] Failed to extract archive (no supported tool found: 7-Zip/WinRAR/tar)." -ForegroundColor Red
        Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue
        return $false
    }

    # Strip wrapping folder if named after the archive or single wrapper
    $archiveBaseName = [System.IO.Path]::GetFileNameWithoutExtension($archivePath)
    $sourceToMove = $tempExtract

    $sameNameDir = Join-Path $tempExtract $archiveBaseName
    if (Test-Path $sameNameDir -PathType Container) {
        $sourceToMove = $sameNameDir
    } else {
        $topItems = Get-ChildItem -Path $tempExtract
        if ($topItems.Count -eq 1 -and $topItems[0].PSIsContainer) {
            $folderName = $topItems[0].Name
            $keepDirs = @("contents", "sound", "prop", "modules", "data", "package", "model", "graphics", "db")
            if ($folderName -match "\s+to\s+" -or $folderName -match "^[A-Za-z0-9_]+-\d+" -or ($keepDirs -notcontains $folderName.ToLower())) {
                $sourceToMove = $topItems[0].FullName
            }
        }
    }

    # Overwrite-merge to destination directory
    robocopy "$sourceToMove" "$destPath" /E /MOVE /NFL /NDL /NJH /NJS | Out-Null
    $roboExit = $LASTEXITCODE

    Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue

    return ($roboExit -lt 8)
}

function Convert-HexStringToBytes([string]$hex) {
    $hex = $hex.Trim() -replace '\s+', ''
    if ($hex.Length % 2 -ne 0) { throw "Hex string length must be even: $hex" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $hex.Length; $i += 2) {
        $bytes[$i / 2] = [Convert]::ToByte($hex.Substring($i, 2), 16)
    }
    return $bytes
}

function Convert-BytesToHexString([byte[]]$bytes) {
    return ($bytes | ForEach-Object { $_.ToString("X2") }) -join ""
}

function Compare-ByteArrays ([byte[]]$a, [byte[]]$b) {
    if ($null -eq $a -or $null -eq $b) { return $false }
    if ($a.Length -ne $b.Length) { return $false }
    for ($i = 0; $i -lt $a.Length; $i++) {
        if ($a[$i] -ne $b[$i]) { return $false }
    }
    return $true
}

$script:backedUpDllsInSession = @{}
function Backup-Dll ($dllPath, [bool]$forceOverwrite = $false) {
    $bakPath = "$dllPath.bak"
    $key = $dllPath.ToLower()
    if (-not (Test-Path $bakPath) -or ($forceOverwrite -and -not $script:backedUpDllsInSession.ContainsKey($key))) {
        Copy-Item -Path $dllPath -Destination $bakPath -Force
        $script:backedUpDllsInSession[$key] = $true
        Write-Host "  [Backup] Saved clean backup: $(Split-Path $bakPath -Leaf)" -ForegroundColor DarkGray
    }
}

function Find-AllTargetDlls ($baseDir, $dllName) {
    if (-not (Test-Path $baseDir)) { return @() }
    $foundPaths = @()
    $seen = @{}
    $candidates = @(
        (Join-Path $baseDir $dllName),
        (Join-Path $baseDir "contents\$dllName"),
        (Join-Path $baseDir "contents\modules\$dllName"),
        (Join-Path $baseDir "modules\$dllName")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c -PathType Leaf) {
            $full = [System.IO.Path]::GetFullPath($c)
            if (-not $seen.ContainsKey($full.ToLower())) {
                $seen[$full.ToLower()] = $true
                $foundPaths += $full
            }
        }
    }
    $recursive = Get-ChildItem -Path $baseDir -Filter $dllName -Recurse -File -ErrorAction SilentlyContinue
    foreach ($f in $recursive) {
        $full = [System.IO.Path]::GetFullPath($f.FullName)
        if (-not $seen.ContainsKey($full.ToLower())) {
            $seen[$full.ToLower()] = $true
            $foundPaths += $full
        }
    }
    return $foundPaths
}

function Get-Sp2xGameCode ($gameCode, $currentVersion) {
    $detected = if ($gameCode) { $gameCode.Split('-')[0].Trim().ToUpper() } else { "" }
    if (-not $detected -and $currentVersion -match "^([A-Za-z0-9_]+)-") {
        $detected = $matches[1].ToUpper()
    }
    return $detected
}

function Get-Sp2xVersionDate ($currentVersion, $resolvedBootstrap) {
    $versionDate = ""
    if ($resolvedBootstrap -and (Test-Path $resolvedBootstrap -PathType Leaf)) {
        $bContent = Get-Content $resolvedBootstrap -Raw -Encoding UTF8
        if ($bContent -match '(?s)<release_code\b[^>]*>\s*([A-Za-z0-9_-]+)\s*</release_code>') {
            $rc = $matches[1].Trim()
            if ($rc -match "^(\d{4})(\d{2})(\d{2})") {
                $versionDate = "$($matches[1])-$($matches[2])-$($matches[3])"
            }
        }
    }
    if (-not $versionDate -and $currentVersion) {
        if ($currentVersion -match "(\d{4}-\d{2}-\d{2})") {
            $versionDate = $matches[1]
        } elseif ($currentVersion -match "(\d{4})(\d{2})(\d{2})") {
            $versionDate = "$($matches[1])-$($matches[2])-$($matches[3])"
        }
    }
    return $versionDate
}

$script:supportedMdUpdatedInSession = $false
function Get-Sp2xMatchedRows ($detectedGameCode, $versionDate, $patchCacheDir) {
    if (-not (Test-Path $patchCacheDir)) {
        New-Item -ItemType Directory -Path $patchCacheDir -Force | Out-Null
    }

    $supportedMdFile = Join-Path $patchCacheDir "SUPPORTED.md"
    $supportedUrl = "https://raw.githubusercontent.com/eamuse/sp2xpatcher/main/SUPPORTED.md"

    if (-not $script:supportedMdUpdatedInSession) {
        try {
            $null = & curl.exe -fsSL --connect-timeout 5 --max-time 15 -o "$supportedMdFile.tmp" "$supportedUrl" 2>&1
            if ($LASTEXITCODE -eq 0 -and (Test-Path "$supportedMdFile.tmp")) {
                Move-Item -Path "$supportedMdFile.tmp" -Destination "$supportedMdFile" -Force
                $script:supportedMdUpdatedInSession = $true
            } else {
                if (Test-Path "$supportedMdFile.tmp") { Remove-Item "$supportedMdFile.tmp" -Force }
            }
        } catch {}
    }

    if (-not (Test-Path $supportedMdFile)) {
        return @()
    }

    $supportedContent = Get-Content $supportedMdFile -Raw -Encoding UTF8
    $matchedRows = @()
    $lines = $supportedContent -split "`r?`n" | Where-Object { $_ -match "^\|" }
    foreach ($line in $lines) {
        $cols = $line.Split('|') | ForEach-Object { $_.Trim() }
        if ($cols.Count -ge 5 -and $cols[1] -ne "Codename" -and $cols[1] -ne "Game Series" -and $cols[1] -notmatch "^-+$") {
            $rowCode = $cols[1].ToUpper()
            $rowFile = $cols[2]
            $rowVer = $cols[3]
            $rowIdRaw = $cols[4]

            $isGameMatch = ($rowCode -eq $detectedGameCode) -or 
                           ($rowCode.StartsWith("$detectedGameCode-")) -or 
                           ($detectedGameCode.StartsWith("$rowCode-"))

            $isVerMatch = ($rowVer -match [regex]::Escape($versionDate))

            if ($isGameMatch -and $isVerMatch) {
                $identifier = ""
                if ($rowIdRaw -match '\[([^\]]+)\]\((?:patches/)?([^\)]+)\)') {
                    $identifier = $matches[2] -replace '\.json$', ''
                } elseif ($rowIdRaw -match '([A-Za-z0-9_-]+)') {
                    $identifier = $matches[1] -replace '\.json$', ''
                }

                if ($identifier) {
                    $matchedRows += [PSCustomObject]@{
                        Codename   = $rowCode
                        Filename   = $rowFile
                        Version    = $rowVer
                        Identifier = $identifier
                    }
                }
            }
        }
    }
    return $matchedRows
}

function Get-Sp2xPatchJson ($identifier, $patchCacheDir) {
    $jsonFile = Join-Path $patchCacheDir "$identifier.json"
    $jsonUrl = "https://raw.githubusercontent.com/eamuse/sp2xpatcher/main/patches/$identifier.json"

    try {
        $null = & curl.exe -fsSL --connect-timeout 5 --max-time 15 -o "$jsonFile.tmp" "$jsonUrl" 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-Path "$jsonFile.tmp")) {
            Move-Item -Path "$jsonFile.tmp" -Destination "$jsonFile" -Force
        } else {
            if (Test-Path "$jsonFile.tmp") { Remove-Item "$jsonFile.tmp" -Force }
        }
    } catch {}

    if (-not (Test-Path $jsonFile)) { return $null }
    try {
        $jsonRaw = Get-Content $jsonFile -Raw -Encoding UTF8
        return ($jsonRaw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

# Pre-Update: Inspect existing DLL(s) against current version's sp2xpatcher JSON and sync applied patches to config.ini
function Sync-Sp2xPatchesFromDll ($targetDir, $gameCode, $currentVersion, $enabledPatchesRaw, $resolvedBootstrap, $configPath) {
    $detectedGameCode = Get-Sp2xGameCode -gameCode $gameCode -currentVersion $currentVersion
    $versionDate = Get-Sp2xVersionDate -currentVersion $currentVersion -resolvedBootstrap $resolvedBootstrap
    if (-not $detectedGameCode -or -not $versionDate) {
        return $enabledPatchesRaw
    }

    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $patchCacheDir = Join-Path $scriptRoot "patches"

    $matchedRows = @(Get-Sp2xMatchedRows -detectedGameCode $detectedGameCode -versionDate $versionDate -patchCacheDir $patchCacheDir)
    if ($matchedRows.Count -eq 0) {
        return $enabledPatchesRaw
    }

    $detectedPatchList = [System.Collections.Generic.List[string]]::new()
    $detectedSeen = @{}

    foreach ($row in $matchedRows) {
        $dllPaths = @(Find-AllTargetDlls -baseDir $targetDir -dllName $row.Filename)
        if ($dllPaths.Count -eq 0) { continue }

        $patchData = Get-Sp2xPatchJson -identifier $row.Identifier -patchCacheDir $patchCacheDir
        if (-not $patchData) { continue }

        foreach ($dllPath in $dllPaths) {
            $fs = $null
            try {
                $fs = [System.IO.File]::Open($dllPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                foreach ($item in $patchData) {
                    if (-not $item.name) { continue }

                    if ($item.type -eq "memory") {
                        $subList = @($item.patches)
                        if ($subList.Count -eq 0) { continue }
                        $allEnabled = $true
                        foreach ($sub in $subList) {
                            $offset = [long]$sub.offset
                            $enBytes = Convert-HexStringToBytes $sub.dataEnabled
                            $disBytes = Convert-HexStringToBytes $sub.dataDisabled
                            if (Compare-ByteArrays $enBytes $disBytes) { $allEnabled = $false; break }
                            if ($fs.Length -lt ($offset + $enBytes.Length)) { $allEnabled = $false; break }
                            $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
                            $curBytes = New-Object byte[] $enBytes.Length
                            $null = $fs.Read($curBytes, 0, $enBytes.Length)
                            if (-not (Compare-ByteArrays $curBytes $enBytes)) {
                                $allEnabled = $false
                                break
                            }
                        }
                        if ($allEnabled) {
                            $baseKey = $item.name.Trim().ToLower()
                            if (-not $detectedSeen.ContainsKey($baseKey)) {
                                $detectedSeen[$baseKey] = $item.name.Trim()
                                $detectedPatchList.Add($item.name.Trim())
                            }
                        }
                    }
                    elseif ($item.type -eq "union") {
                        $optList = @($item.patches)
                        if ($optList.Count -eq 0) { continue }

                        # Check if Default option matches first
                        $defOpts = @($optList | Where-Object { $_.name -match '(?i)\bdefault\b' })
                        $isDefault = $false
                        foreach ($defOpt in $defOpts) {
                            $subList = @($defOpt.patch)
                            if ($subList.Count -eq 0) { continue }
                            $allMatchDef = $true
                            foreach ($sub in $subList) {
                                $offset = [long]$sub.offset
                                $defBytes = Convert-HexStringToBytes $sub.data
                                if ($fs.Length -lt ($offset + $defBytes.Length)) { $allMatchDef = $false; break }
                                $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
                                $curBytes = New-Object byte[] $defBytes.Length
                                $null = $fs.Read($curBytes, 0, $defBytes.Length)
                                if (-not (Compare-ByteArrays $curBytes $defBytes)) {
                                    $allMatchDef = $false
                                    break
                                }
                            }
                            if ($allMatchDef) { $isDefault = $true; break }
                        }

                        if (-not $isDefault) {
                            foreach ($opt in $optList) {
                                if ($opt.name -match '(?i)\bdefault\b') { continue }
                                $subList = @($opt.patch)
                                if ($subList.Count -eq 0) { continue }
                                $allMatchOpt = $true
                                foreach ($sub in $subList) {
                                    $offset = [long]$sub.offset
                                    $optBytes = Convert-HexStringToBytes $sub.data
                                    if ($fs.Length -lt ($offset + $optBytes.Length)) { $allMatchOpt = $false; break }
                                    $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
                                    $curBytes = New-Object byte[] $optBytes.Length
                                    $null = $fs.Read($curBytes, 0, $optBytes.Length)
                                    if (-not (Compare-ByteArrays $curBytes $optBytes)) {
                                        $allMatchOpt = $false
                                        break
                                    }
                                }
                                if ($allMatchOpt) {
                                    $baseKey = $item.name.Trim().ToLower()
                                    $entryStr = "$($item.name.Trim()):$($opt.name.Trim())"
                                    if (-not $detectedSeen.ContainsKey($baseKey)) {
                                        $detectedSeen[$baseKey] = $entryStr
                                        $detectedPatchList.Add($entryStr)
                                    }
                                    break
                                }
                            }
                        }
                    }
                }
            } catch {} finally {
                if ($fs) { $fs.Close() }
            }
        }
    }

    if ($detectedPatchList.Count -eq 0) {
        return $enabledPatchesRaw
    }

    # Merge detected patches with existing EnabledPatches in config.ini
    $mergedList = [System.Collections.Generic.List[string]]::new()
    $existingBaseMap = @{}

    if (-not [string]::IsNullOrWhiteSpace($enabledPatchesRaw)) {
        foreach ($p in $enabledPatchesRaw.Split(',')) {
            $trimmed = $p.Trim()
            if ($trimmed -ne "") {
                $baseName = if ($trimmed.Contains(":")) { $trimmed.Substring(0, $trimmed.IndexOf(":")).Trim().ToLower() } else { $trimmed.ToLower() }
                if (-not $existingBaseMap.ContainsKey($baseName)) {
                    $existingBaseMap[$baseName] = $mergedList.Count
                    $mergedList.Add($trimmed)
                }
            }
        }
    }

    $newlyAdded = [System.Collections.Generic.List[string]]::new()
    foreach ($det in $detectedPatchList) {
        $detBase = if ($det.Contains(":")) { $det.Substring(0, $det.IndexOf(":")).Trim().ToLower() } else { $det.ToLower() }
        if (-not $existingBaseMap.ContainsKey($detBase)) {
            $existingBaseMap[$detBase] = $mergedList.Count
            $mergedList.Add($det)
            $newlyAdded.Add($det)
        }
    }

    $updatedRaw = ($mergedList -join ", ")
    if ($newlyAdded.Count -gt 0) {
        Write-Host "`n[sp2xpatcher] Detected applied patch(es) from existing DLL ($detectedGameCode $versionDate):" -ForegroundColor Cyan
        foreach ($np in $newlyAdded) {
            Write-Host "  + $np" -ForegroundColor Green
        }
        Set-ConfigIniValue -configPath $configPath -keyName "EnabledPatches" -newValue $updatedRaw
        Write-Host "[sp2xpatcher] Saved detected patch list to config.ini (EnabledPatches)." -ForegroundColor Green
    } else {
        Write-Host "[sp2xpatcher] Verified $($detectedPatchList.Count) active patch(es) on existing DLL ($versionDate)." -ForegroundColor Gray
    }

    return $updatedRaw
}

function Invoke-Sp2xPatcher ($targetDir, $gameCode, $currentVersion, $enabledPatchesRaw, $resolvedBootstrap, [bool]$forceNewBackup = $false) {
    Write-Host "`n----------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "[sp2xpatcher] Checking for game patches..." -ForegroundColor Yellow

    $detectedGameCode = Get-Sp2xGameCode -gameCode $gameCode -currentVersion $currentVersion
    if (-not $detectedGameCode) {
        Write-Host "[sp2xpatcher] Could not determine Game ID. Please specify GameID in config.ini." -ForegroundColor Yellow
        return
    }

    $versionDate = Get-Sp2xVersionDate -currentVersion $currentVersion -resolvedBootstrap $resolvedBootstrap
    if (-not $versionDate) {
        Write-Host "[sp2xpatcher] Could not detect game release date from bootstrap.xml or version string." -ForegroundColor Yellow
        return
    }

    Write-Host "[sp2xpatcher] Target Game: $detectedGameCode | Date: $versionDate" -ForegroundColor Cyan

    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $patchCacheDir = Join-Path $scriptRoot "patches"

    $matchedRows = @(Get-Sp2xMatchedRows -detectedGameCode $detectedGameCode -versionDate $versionDate -patchCacheDir $patchCacheDir)
    if ($matchedRows.Count -eq 0) {
        Write-Host "[sp2xpatcher] No patch definitions found for $detectedGameCode ($versionDate) in SUPPORTED.md." -ForegroundColor Yellow
        return
    }

    $configuredPatches = @()
    if (-not [string]::IsNullOrWhiteSpace($enabledPatchesRaw)) {
        $configuredPatches = @($enabledPatchesRaw.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    }

    $foundInAnyJson = @{}

    foreach ($row in $matchedRows) {
        Write-Host "`n[sp2xpatcher] Matched: $($row.Filename) (Identifier: $($row.Identifier))" -ForegroundColor Cyan
        
        $targetDlls = @(Find-AllTargetDlls -baseDir $targetDir -dllName $row.Filename)
        if ($targetDlls.Count -eq 0) {
            Write-Host "  -> '$($row.Filename)' was not found in '$targetDir'. Skipping." -ForegroundColor DarkGray
            continue
        }

        $patchData = Get-Sp2xPatchJson -identifier $row.Identifier -patchCacheDir $patchCacheDir
        if (-not $patchData) {
            Write-Host "  -> Failed to load or parse patch definition file: $($row.Identifier).json" -ForegroundColor Red
            continue
        }

        if ($configuredPatches.Count -eq 0) {
            Write-Host "  Available patches for $($row.Filename):" -ForegroundColor Green
            foreach ($item in $patchData) {
                if ($item.type -eq "memory") {
                    Write-Host "    - $($item.name)" -ForegroundColor White
                } elseif ($item.type -eq "union") {
                    $opts = ($item.patches | ForEach-Object { $_.name }) -join " | "
                    Write-Host "    - $($item.name): <$opts>" -ForegroundColor White
                }
            }
            continue
        }

        foreach ($patchStr in $configuredPatches) {
            $pName = $patchStr
            $optName = ""
            if ($patchStr.Contains(":")) {
                $colonIdx = $patchStr.IndexOf(":")
                $pName = $patchStr.Substring(0, $colonIdx).Trim()
                $optName = $patchStr.Substring($colonIdx + 1).Trim()
            }

            $matchedDef = $patchData | Where-Object { $_.name -and ($_.name.Trim().ToLower() -eq $pName.ToLower()) } | Select-Object -First 1
            if (-not $matchedDef) {
                continue
            }

            $foundInAnyJson[$pName.ToLower()] = $true

            if ($matchedDef.type -eq "memory") {
                $subPatches = @($matchedDef.patches)
                $dllGroups = $subPatches | Group-Object { if ($_.dllName) { $_.dllName } else { $row.Filename } }
                foreach ($grp in $dllGroups) {
                    $dllName = $grp.Name
                    $dllPaths = @(Find-AllTargetDlls -baseDir $targetDir -dllName $dllName)
                    if ($dllPaths.Count -eq 0) {
                        Write-Host "  [WARN] '$dllName' not found for patch '$pName'." -ForegroundColor Yellow
                        continue
                    }

                    foreach ($dllPath in $dllPaths) {
                        $relDll = if ($dllPath.StartsWith($targetDir, [System.StringComparison]::OrdinalIgnoreCase)) { $dllPath.Substring($targetDir.Length).TrimStart('\', '/') } else { Split-Path $dllPath -Leaf }
                        $appliedCount = 0
                        $alreadyCount = 0
                        $mismatchCount = 0
                        $firstOffset = [long]0

                        $fs = [System.IO.File]::Open($dllPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
                        try {
                            foreach ($sub in $grp.Group) {
                                $offset = [long]$sub.offset
                                $disabledBytes = Convert-HexStringToBytes $sub.dataDisabled
                                $enabledBytes = Convert-HexStringToBytes $sub.dataEnabled
                                $patchLen = $enabledBytes.Length

                                if ($fs.Length -lt ($offset + $patchLen)) {
                                    Write-Host "  [WARN] '$pName' ($relDll): File size is smaller than offset 0x$($offset.ToString('X'))." -ForegroundColor Red
                                    $mismatchCount++
                                    continue
                                }
                                $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
                                $curBytes = New-Object byte[] $patchLen
                                $null = $fs.Read($curBytes, 0, $patchLen)

                                if (Compare-ByteArrays $curBytes $enabledBytes) {
                                    $alreadyCount++
                                } elseif (Compare-ByteArrays $curBytes $disabledBytes) {
                                    Backup-Dll -dllPath $dllPath -forceOverwrite $forceNewBackup
                                    $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
                                    $fs.Write($enabledBytes, 0, $patchLen)
                                    if ($appliedCount -eq 0) { $firstOffset = $offset }
                                    $appliedCount++
                                } else {
                                    $curHex = Convert-BytesToHexString $curBytes
                                    Write-Host "  [WARN] '$($matchedDef.name)' ($relDll): Byte mismatch at 0x$($offset.ToString('X')). Found: $curHex, Expected: $($sub.dataDisabled). Skipped." -ForegroundColor Yellow
                                    $mismatchCount++
                                }
                            }
                        } finally {
                            $fs.Close()
                        }

                        if ($appliedCount -gt 0) {
                            $offsetInfo = if ($appliedCount -eq 1) { "Offset: 0x$($firstOffset.ToString('X'))" } else { "$appliedCount offsets" }
                            Write-Host "  [OK] Applied '$($matchedDef.name)' to $relDll ($offsetInfo)" -ForegroundColor Green
                        } elseif ($alreadyCount -gt 0 -and $mismatchCount -eq 0) {
                            Write-Host "  [OK] '$($matchedDef.name)' ($relDll): Already applied." -ForegroundColor DarkGreen
                        }
                    }
                }
            }
            elseif ($matchedDef.type -eq "union") {
                if (-not $optName) {
                    $availOpts = ($matchedDef.patches | ForEach-Object { $_.name }) -join ", "
                    Write-Host "  [WARN] '$($matchedDef.name)' is a union patch. Please specify an option in config.ini (e.g. '$($matchedDef.name):Option'). Available: $availOpts" -ForegroundColor Yellow
                    continue
                }

                $matchedOption = $matchedDef.patches | Where-Object {
                    $_.name.Trim().ToLower() -eq $optName.ToLower() -or
                    $_.name.Trim().ToLower().StartsWith($optName.ToLower())
                } | Select-Object -First 1

                if (-not $matchedOption) {
                    $availOpts = ($matchedDef.patches | ForEach-Object { $_.name }) -join ", "
                    Write-Host "  [WARN] Option '$optName' not found for '$($matchedDef.name)'. Available: $availOpts" -ForegroundColor Yellow
                    continue
                }

                $subPatches = @($matchedOption.patch)
                $dllGroups = $subPatches | Group-Object { if ($_.dllName) { $_.dllName } else { $row.Filename } }
                foreach ($grp in $dllGroups) {
                    $dllName = $grp.Name
                    $dllPaths = @(Find-AllTargetDlls -baseDir $targetDir -dllName $dllName)
                    if ($dllPaths.Count -eq 0) {
                        Write-Host "  [WARN] '$dllName' not found for patch '$pName'." -ForegroundColor Yellow
                        continue
                    }

                    foreach ($dllPath in $dllPaths) {
                        $relDll = if ($dllPath.StartsWith($targetDir, [System.StringComparison]::OrdinalIgnoreCase)) { $dllPath.Substring($targetDir.Length).TrimStart('\', '/') } else { Split-Path $dllPath -Leaf }
                        $appliedCount = 0
                        $alreadyCount = 0
                        $firstOffset = [long]0

                        $fs = [System.IO.File]::Open($dllPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
                        try {
                            foreach ($sub in $grp.Group) {
                                $offset = [long]$sub.offset
                                $patchBytes = Convert-HexStringToBytes $sub.data
                                $patchLen = $patchBytes.Length

                                if ($fs.Length -lt ($offset + $patchLen)) {
                                    Write-Host "  [WARN] '$pName' ($relDll): File size is smaller than offset 0x$($offset.ToString('X'))." -ForegroundColor Red
                                    continue
                                }
                                $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
                                $curBytes = New-Object byte[] $patchLen
                                $null = $fs.Read($curBytes, 0, $patchLen)

                                if (Compare-ByteArrays $curBytes $patchBytes) {
                                    $alreadyCount++
                                } else {
                                    Backup-Dll -dllPath $dllPath -forceOverwrite $forceNewBackup
                                    $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
                                    $fs.Write($patchBytes, 0, $patchLen)
                                    if ($appliedCount -eq 0) { $firstOffset = $offset }
                                    $appliedCount++
                                }
                            }
                        } finally {
                            $fs.Close()
                        }

                        if ($appliedCount -gt 0) {
                            $offsetInfo = if ($appliedCount -eq 1) { "Offset: 0x$($firstOffset.ToString('X'))" } else { "$appliedCount offsets" }
                            Write-Host "  [OK] Applied '$($matchedDef.name)' -> '$($matchedOption.name)' to $relDll ($offsetInfo)" -ForegroundColor Green
                        } elseif ($alreadyCount -gt 0) {
                            Write-Host "  [OK] '$($matchedDef.name)' ($($matchedOption.name)) ($relDll): Already applied." -ForegroundColor DarkGreen
                        }
                    }
                }
            }
        }
    }

    if ($configuredPatches.Count -eq 0) {
        Write-Host "`nTo enable any of the above patches, add them to 'EnabledPatches' in config.ini." -ForegroundColor Gray
    } else {
        foreach ($patchStr in $configuredPatches) {
            $checkName = if ($patchStr.Contains(":")) { $patchStr.Substring(0, $patchStr.IndexOf(":")).Trim() } else { $patchStr.Trim() }
            if (-not $foundInAnyJson.ContainsKey($checkName.ToLower())) {
                Write-Host "  [Notice] Patch '$checkName' was not found in patch definitions for $detectedGameCode." -ForegroundColor DarkGray
            }
        }
    }
}

# 3.5. Pre-update: Inspect existing DLL(s) and sync applied patches to config.ini before updating
if ($enableSp2xPatcher -and -not [string]::IsNullOrWhiteSpace($currentVersion)) {
    $enabledPatchesRaw = Sync-Sp2xPatchesFromDll -targetDir $targetDir -gameCode $gameId -currentVersion $currentVersion -enabledPatchesRaw $enabledPatchesRaw -resolvedBootstrap $resolvedBootstrap -configPath $ConfigFile
}

# 4. Plan and validate sequential updates
$plannedPatches = @()
$canUpdate = $true
$gameCode = if ($gameId) { $gameId } else { "" }
if (-not $gameCode -and $currentVersion -match "^([A-Za-z0-9_]+)-") {
    $gameCode = $matches[1]
}

if (-not [string]::IsNullOrWhiteSpace($currentVersion) -and $patchList.Count -gt 0) {
    # Parse available patches to find the highest server version
    $availablePatches = @()
    foreach ($f in $patchList) {
        if ($f -match "^([A-Za-z0-9_]+)-(\d+)\s+to\s+([A-Za-z0-9_-]+)\.rar$") {
            $pGame = $matches[1]
            $pFromNum = [long]$matches[2]
            $pToRaw = $matches[3]
            $pToNum = 0
            if ($pToRaw -match "(\d+)$") { $pToNum = [long]$matches[1] }
            $availablePatches += [PSCustomObject]@{
                FileName   = $f
                GameCode   = $pGame
                FromVerNum = $pFromNum
                ToVerNum   = $pToNum
            }
        }
    }

    $maxServerVerNum = 0
    if ($availablePatches.Count -gt 0) {
        $maxServerVerNum = ($availablePatches | Measure-Object -Property ToVerNum -Maximum).Maximum
    }

    $curVerNum = 0
    if ($currentVersion -match "-(\d+)$") {
        $curVerNum = [long]$matches[1]
    } elseif ($currentVersion -match "^\d+$") {
        $curVerNum = [long]$currentVersion
    }

    # Trace patch chain from current version
    $tempVer = $currentVersion
    while ($true) {
        $escapedVer = [regex]::Escape($tempVer)
        $matchedFile = $patchList | Where-Object { $_ -match "^$escapedVer\s+to\s+([A-Za-z0-9_-]+)\.rar$" } | Select-Object -First 1
        if (-not $matchedFile) { break }

        if ($matchedFile -match "^$escapedVer\s+to\s+([A-Za-z0-9_-]+)\.rar$") {
            $nextVerSuffix = $matches[1]
            $newFullVersion = if ($nextVerSuffix -match "^[A-Za-z0-9_]+-") { $nextVerSuffix }
                              elseif ($gameCode) { "$gameCode-$nextVerSuffix" }
                              else { $nextVerSuffix }

            $plannedPatches += [PSCustomObject]@{
                FileName    = $matchedFile
                FromVersion = $tempVer
                ToVersion   = $newFullVersion
            }
            $tempVer = $newFullVersion
        }
    }

    $plannedEndNum = 0
    if ($tempVer -match "-(\d+)$") {
        $plannedEndNum = [long]$matches[1]
    } elseif ($tempVer -match "(\d+)$") {
        $plannedEndNum = [long]$matches[1]
    }

    # Validation: Check if patch from current version or intermediate patch is missing
    if ($curVerNum -gt 0 -and $maxServerVerNum -gt 0 -and $curVerNum -lt $maxServerVerNum) {
        if ($plannedPatches.Count -eq 0) {
            $canUpdate = $false
            Write-Host "`n[WARNING] Update cannot proceed: Missing required patch file!" -ForegroundColor Red
            Write-Host "  Current game version : $currentVersion" -ForegroundColor Yellow
            Write-Host "  Latest server version: $maxServerVerNum" -ForegroundColor Yellow
            Write-Host "  Missing patch file   : $currentVersion to <next_version>.rar" -ForegroundColor Red
            Write-Host "The patch file to update from current version to next version is missing on server." -ForegroundColor Red
            Write-Host "Update aborted.`n" -ForegroundColor Red
        }
        elseif ($plannedEndNum -lt $maxServerVerNum) {
            $canUpdate = $false
            Write-Host "`n[WARNING] Update cannot proceed: Incomplete update chain on server!" -ForegroundColor Red
            Write-Host "  Current game version : $currentVersion" -ForegroundColor Yellow
            Write-Host "  Chain stopped at     : $tempVer" -ForegroundColor Yellow
            Write-Host "  Latest server version: $maxServerVerNum" -ForegroundColor Yellow
            Write-Host "  Missing patch file   : $tempVer to <next_version>.rar" -ForegroundColor Red
            Write-Host "An intermediate patch file in the update chain is missing on server." -ForegroundColor Red
            Write-Host "Update aborted to prevent partial update.`n" -ForegroundColor Red
        }
    }
}

# 5. Execute sequential update loop
$updateCount = 0

if ($canUpdate -and $plannedPatches.Count -gt 0) {
    Write-Host "`nFound $($plannedPatches.Count) sequential patch(es) to apply:" -ForegroundColor Cyan
    foreach ($p in $plannedPatches) {
        Write-Host "  $($p.FromVersion) -> $($p.ToVersion) ($($p.FileName))" -ForegroundColor Gray
    }

    try {
        foreach ($p in $plannedPatches) {
            $updateCount++
            Write-Host "`n----------------------------------------------------------" -ForegroundColor DarkGray
            Write-Host "[Step $updateCount / $($plannedPatches.Count)] Updating: $($p.FromVersion) -> $($p.ToVersion)" -ForegroundColor Yellow
            Write-Host "Patch file : $($p.FileName)" -ForegroundColor White

            $tempFile = Join-Path $localTempDir "patch_$updateCount.rar"
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force }

            $encodedFileName = [System.Uri]::EscapeDataString($p.FileName)
            $downloadUrl = "$serverUrl/$encodedFileName"

            Write-Host "Downloading..." -ForegroundColor Gray
            & curl.exe -fSL --progress-bar -o "$tempFile" "$downloadUrl"

            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tempFile)) {
                Write-Host "[ERROR] Failed to download patch: $($p.FileName)" -ForegroundColor Red
                break
            }

            Write-Host "Applying patch..." -ForegroundColor Yellow
            $unpacked = Unpack-Archive -archivePath $tempFile -destPath $targetDir -workTempDir $localTempDir

            if (Test-Path $tempFile) { Remove-Item $tempFile -Force }

            if (-not $unpacked) {
                Write-Host "[ERROR] Failed to extract and apply patch." -ForegroundColor Red
                break
            }

            $currentVersion = $p.ToVersion
            Write-Host "[OK] Applied v$currentVersion" -ForegroundColor Green
        }
    } finally {
        # Clean up local temporary folder
        if (Test-Path $localTempDir) {
            Remove-Item -Recurse -Force $localTempDir -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
if ($updateCount -gt 0) {
    Write-Host "Successfully applied $($updateCount) patch(es)!" -ForegroundColor Green
    Write-Host "Latest version: $currentVersion" -ForegroundColor White
} elseif ($canUpdate -and $serverReachable) {
    Write-Host "Already up to date. No new patches available." -ForegroundColor Green
    if ($currentVersion) {
        Write-Host "Current version: $currentVersion" -ForegroundColor White
    }
}
Write-Host "==========================================================" -ForegroundColor Cyan

# 6. Post-processing
if ($updateCount -gt 0) {
    $dateCode = ""
    if ($currentVersion -match "-(\d+)$") {
        $dateCode = $matches[1]
    } elseif ($currentVersion -match "(\d{8,12})") {
        $dateCode = $matches[1]
    }

    # 6-1. Update datecode in ea3-config.xml and sync bootstrap.xml (auto-detect in target directory)
    if (-not [string]::IsNullOrWhiteSpace($dateCode)) {
        $resolvedEa3 = ""
        if ($resolvedBootstrap) {
            $candidate = Join-Path (Split-Path -Parent $resolvedBootstrap) "ea3-config.xml"
            if (Test-Path $candidate -PathType Leaf) { $resolvedEa3 = $candidate }
        }
        if (-not $resolvedEa3) {
            $ea3Candidates = @(
                (Join-Path $targetDir "contents\prop\ea3-config.xml"),
                (Join-Path $targetDir "prop\ea3-config.xml"),
                (Join-Path $targetDir "ea3-config.xml")
            )
            foreach ($c in $ea3Candidates) {
                if (Test-Path $c -PathType Leaf) {
                    $resolvedEa3 = $c
                    break
                }
            }
        }
        if (-not $resolvedEa3) {
            $foundEa3 = Get-ChildItem -Path $targetDir -Filter "ea3-config.xml" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($foundEa3) { $resolvedEa3 = $foundEa3.FullName }
        }

        if ($resolvedEa3 -and (Test-Path $resolvedEa3 -PathType Leaf)) {
            $xmlContent = Get-Content $resolvedEa3 -Raw -Encoding UTF8
            if ($xmlContent -match '<ext\s+__type="str">[^<]*</ext>') {
                $newXml = [regex]::Replace($xmlContent, '<ext\s+__type="str">[^<]*</ext>', "<ext __type=`"str`">$dateCode</ext>")
                [System.IO.File]::WriteAllText($resolvedEa3, $newXml, [System.Text.Encoding]::UTF8)
                Write-Host "`n[Post-Process] Updated ea3-config.xml (<ext __type=`"str`">$dateCode</ext>)" -ForegroundColor Green
            }
        }

        # Verify bootstrap.xml release_code matches the applied update
        if (-not $resolvedBootstrap -or -not (Test-Path $resolvedBootstrap -PathType Leaf)) {
            if ($resolvedEa3) {
                $candidate = Join-Path (Split-Path -Parent $resolvedEa3) "bootstrap.xml"
                if (Test-Path $candidate -PathType Leaf) { $resolvedBootstrap = $candidate }
            }
            if (-not $resolvedBootstrap) {
                $bootstrapCandidates = @(
                    (Join-Path $targetDir "contents\prop\bootstrap.xml"),
                    (Join-Path $targetDir "prop\bootstrap.xml"),
                    (Join-Path $targetDir "bootstrap.xml")
                )
                foreach ($c in $bootstrapCandidates) {
                    if (Test-Path $c -PathType Leaf) { $resolvedBootstrap = $c; break }
                }
            }
            if (-not $resolvedBootstrap) {
                $foundB = Get-ChildItem -Path $targetDir -Filter "bootstrap.xml" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($foundB) { $resolvedBootstrap = $foundB.FullName }
            }
        }

        if ($resolvedBootstrap -and (Test-Path $resolvedBootstrap -PathType Leaf)) {
            $bContent = Get-Content $resolvedBootstrap -Raw -Encoding UTF8
            if ($bContent -match '(?s)<release_code\b[^>]*>\s*([A-Za-z0-9_-]+)\s*</release_code>') {
                $actualReleaseCode = $matches[1].Trim()
                if ($actualReleaseCode -eq $dateCode) {
                    Write-Host "[Verify] bootstrap.xml release_code verified: $actualReleaseCode" -ForegroundColor Green
                } else {
                    Write-Host "[WARNING] bootstrap.xml release_code mismatch! (Expected: $dateCode, Found: $actualReleaseCode)" -ForegroundColor Red
                }
            } else {
                Write-Host "[WARNING] Could not parse <release_code> in bootstrap.xml." -ForegroundColor Red
            }
        } else {
            Write-Host "[WARNING] bootstrap.xml not found after applying patch." -ForegroundColor Red
        }
    }

    # 6-2. Copy files inside modules to parent directory
    if ($moveModulesUp) {
        $modulesFullPath = ""
        if (-not [string]::IsNullOrWhiteSpace($modulesDir)) {
            $modulesFullPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $modulesDir))
        } else {
            $candidates = @(
                (Join-Path $targetDir "contents\modules"),
                (Join-Path $targetDir "modules")
            )
            foreach ($c in $candidates) {
                if (Test-Path $c -PathType Container) {
                    $modulesFullPath = $c
                    break
                }
            }
        }

        if ($modulesFullPath -and (Test-Path $modulesFullPath -PathType Container)) {
            $parentDir = Split-Path -Parent $modulesFullPath
            robocopy "$modulesFullPath" "$parentDir" /E /NFL /NDL /NJH /NJS | Out-Null
            Write-Host "[Post-Process] Copied modules to parent directory" -ForegroundColor Green
        }
    }
}

# 6-3. sp2xpatcher Binary DLL Patching (Applies detected/configured patches to the current/updated DLL)
if ($enableSp2xPatcher -and $canUpdate) {
    Invoke-Sp2xPatcher -targetDir $targetDir -gameCode $gameId -currentVersion $currentVersion -enabledPatchesRaw $enabledPatchesRaw -resolvedBootstrap $resolvedBootstrap -forceNewBackup ($updateCount -gt 0)
}

# 7. Countdown and auto-exit
Write-Host "`nWindow will close in 5 seconds... (Press any key to exit now)" -ForegroundColor Gray
for ($i = 5; $i -gt 0; $i--) {
    Write-Host -NoNewline "`rClosing in $i second(s)... " -ForegroundColor Yellow
    $keyPressed = $false
    try {
        if ([Console]::KeyAvailable) {
            $null = [Console]::ReadKey($true)
            $keyPressed = $true
        }
    } catch {}
    if ($keyPressed) { break }
    Start-Sleep -Seconds 1
}
Write-Host "`rClosing window...               " -ForegroundColor Green
