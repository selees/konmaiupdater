param (
    [string]$ConfigFile = "$PSScriptRoot\config.ini",
    [string]$VersionFile = "$PSScriptRoot\version.txt"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$host.UI.RawUI.WindowTitle = "KONMAI Game Auto Updater"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "              KONMAI Game Auto Updater                    " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Load config.ini
$serverUrl = "http://localhost:8080"
$gameId = ""
$targetDir = "$PSScriptRoot"
$ea3ConfigPath = ""
$bootstrapPath = ""
$moveModulesUp = $false
$modulesDir = ""

# Local temporary directory inside the updater folder
$localTempDir = Join-Path $PSScriptRoot "_temp"
if (-not (Test-Path $localTempDir)) {
    New-Item -ItemType Directory -Path $localTempDir -Force | Out-Null
}

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
        elseif ($line -match "^Ea3ConfigPath\s*=\s*(.+)$") {
            $ea3ConfigPath = $matches[1].Trim()
        }
        elseif ($line -match "^BootstrapPath\s*=\s*(.+)$") {
            $bootstrapPath = $matches[1].Trim()
        }
        elseif ($line -match "^MoveModulesUp\s*=\s*(.+)$") {
            $moveModulesUp = ($matches[1].Trim().ToLower() -eq "true")
        }
        elseif ($line -match "^ModulesDir\s*=\s*(.+)$") {
            $modulesDir = $matches[1].Trim()
        }
    }
} else {
    @"
[Server]
; Web server URL (e.g. http://192.168.0.10:8080)
ServerUrl=http://localhost:8080

[Update]
; Game ID code to match patches (e.g. KFC, MDX, LDJ)
GameID=KFC

; Target game directory (. for current directory, or ./KFC for subfolder)
TargetDir=./KFC

[Ea3Config]
; Path to ea3-config.xml (relative or absolute, leave empty to disable)
Ea3ConfigPath=./KFC/contents/prop/ea3-config.xml

; Path to bootstrap.xml (leave empty to auto-detect in the same folder as ea3-config.xml)
BootstrapPath=

[Modules]
; Copy files inside modules to parent folder (true / false)
MoveModulesUp=true
; Modules directory path (leave empty to auto-detect inside TargetDir)
ModulesDir=./KFC/contents/modules
"@ | Set-Content -Path $ConfigFile -Encoding UTF8
    Write-Host "[Notice] Created default config.ini" -ForegroundColor Gray
}

Write-Host "Server URL : $serverUrl" -ForegroundColor White
Write-Host "Game ID    : $(if ($gameId) { $gameId } else { 'ALL' })" -ForegroundColor White
Write-Host "Target Dir : $targetDir" -ForegroundColor White

# 2. Query available patches from server
Write-Host "`nChecking for available patches..." -ForegroundColor Yellow

$patchList = @()
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
    Write-Host "[ERROR] Could not connect to update server ($serverUrl)." -ForegroundColor Red
    Write-Host "Please ensure the server is running and the IP address in config.ini is correct." -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor DarkGray
    exit 1
}

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

# 3. Detect current game version from bootstrap.xml (or fallback to version.txt)
$currentVersion = ""
$resolvedBootstrap = ""

# Locate bootstrap.xml (in the same folder as ea3-config.xml or specified path)
if (-not [string]::IsNullOrWhiteSpace($bootstrapPath)) {
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $bootstrapPath))
    if (Test-Path $candidate -PathType Leaf) { $resolvedBootstrap = $candidate }
}
if (-not $resolvedBootstrap -and -not [string]::IsNullOrWhiteSpace($ea3ConfigPath)) {
    $ea3Dir = Split-Path -Parent ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $ea3ConfigPath)))
    $candidate = Join-Path $ea3Dir "bootstrap.xml"
    if (Test-Path $candidate -PathType Leaf) { $resolvedBootstrap = $candidate }
}
if (-not $resolvedBootstrap) {
    $candidates = @(
        (Join-Path $targetDir "contents\prop\bootstrap.xml"),
        (Join-Path $targetDir "prop\bootstrap.xml"),
        (Join-Path $targetDir "bootstrap.xml")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c -PathType Leaf) {
            $resolvedBootstrap = $c
            break
        }
    }
}

# Inspect <release_code> from bootstrap.xml if found
if ($resolvedBootstrap -and (Test-Path $resolvedBootstrap -PathType Leaf)) {
    $bContent = Get-Content $resolvedBootstrap -Raw -Encoding UTF8
    if ($bContent -match '(?s)<release_code\b[^>]*>\s*([A-Za-z0-9_-]+)\s*</release_code>') {
        $releaseCode = $matches[1].Trim()
        $currentVersion = if ($gameId) { "$gameId-$releaseCode" } else { $releaseCode }
        Write-Host "`n[Notice] Game version detected from bootstrap.xml: $currentVersion" -ForegroundColor Cyan
        $currentVersion | Set-Content -Path $VersionFile -Encoding UTF8
    }
}

# Fallback to version.txt if not detected from bootstrap.xml
if (-not $currentVersion -and (Test-Path $VersionFile)) {
    $currentVersion = (Get-Content $VersionFile -Raw -Encoding UTF8).Trim()
    if ($gameId -and $currentVersion -match "^\d+$") {
        $currentVersion = "$gameId-$currentVersion"
    }
    if ($currentVersion) {
        Write-Host "`n[Notice] Game version loaded from version.txt: $currentVersion" -ForegroundColor Cyan
    }
}

# Fallback to server lowest patch if version is still unknown
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
        Write-Host "`n[Notice] No existing version found in bootstrap.xml or version.txt." -ForegroundColor Cyan
        Write-Host "  -> Starting sequential update for [$($lowestPatch.GameCode)] from base version: $currentVersion" -ForegroundColor Green
        $currentVersion | Set-Content -Path $VersionFile -Encoding UTF8
    } else {
        Write-Host "[ERROR] No valid patch naming format found for Game ID [$gameId]." -ForegroundColor Red
        exit 1
    }
}

if (-not [string]::IsNullOrWhiteSpace($currentVersion)) {
    Write-Host "Current Ver: $currentVersion" -ForegroundColor Green
}
Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray

# Helper function: Unpack archive with auto wrapper-folder stripping using local temp
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

# 4. Sequential update loop
$updateCount = 0

try {
    if (-not [string]::IsNullOrWhiteSpace($currentVersion)) {
        while ($true) {
            $gameCode = if ($gameId) { $gameId } else { "" }
            if (-not $gameCode -and $currentVersion -match "^([A-Za-z0-9_]+)-") {
                $gameCode = $matches[1]
            }

            $escapedCurVer = [regex]::Escape($currentVersion)
            $matchedFile = $patchList | Where-Object { $_ -match "^$escapedCurVer\s+to\s+([A-Za-z0-9_-]+)\.rar$" } | Select-Object -First 1

            if (-not $matchedFile) {
                break
            }

            if ($matchedFile -match "^$escapedCurVer\s+to\s+([A-Za-z0-9_-]+)\.rar$") {
                $nextVerSuffix = $matches[1]
            } else {
                break
            }

            if ($nextVerSuffix -match "^[A-Za-z0-9_]+-") {
                $newFullVersion = $nextVerSuffix
            } elseif ($gameCode) {
                $newFullVersion = "$gameCode-$nextVerSuffix"
            } else {
                $newFullVersion = $nextVerSuffix
            }

            $updateCount++
            Write-Host "`n----------------------------------------------------------" -ForegroundColor DarkGray
            Write-Host "[Step $updateCount] Updating: $currentVersion -> $newFullVersion" -ForegroundColor Yellow
            Write-Host "Patch file : $matchedFile" -ForegroundColor White

            $tempFile = Join-Path $localTempDir "patch_$updateCount.rar"
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force }

            $encodedFileName = [System.Uri]::EscapeDataString($matchedFile)
            $downloadUrl = "$serverUrl/$encodedFileName"

            Write-Host "Downloading..." -ForegroundColor Gray
            & curl.exe -fSL --progress-bar -o "$tempFile" "$downloadUrl"

            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tempFile)) {
                Write-Host "[ERROR] Failed to download patch: $matchedFile" -ForegroundColor Red
                exit 1
            }

            Write-Host "Applying patch..." -ForegroundColor Yellow
            $unpacked = Unpack-Archive -archivePath $tempFile -destPath $targetDir -workTempDir $localTempDir

            if (Test-Path $tempFile) { Remove-Item $tempFile -Force }

            if (-not $unpacked) {
                Write-Host "[ERROR] Failed to extract and apply patch." -ForegroundColor Red
                exit 1
            }

            $newFullVersion | Set-Content -Path $VersionFile -Encoding UTF8
            $currentVersion = $newFullVersion

            Write-Host "[OK] Applied v$currentVersion" -ForegroundColor Green
        }
    }
} finally {
    # Clean up local temporary folder
    if (Test-Path $localTempDir) {
        Remove-Item -Recurse -Force $localTempDir -ErrorAction SilentlyContinue
    }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
if ($updateCount -gt 0) {
    Write-Host "Successfully applied $($updateCount) patch(es)!" -ForegroundColor Green
    Write-Host "Latest version: $currentVersion" -ForegroundColor White
} else {
    Write-Host "Already up to date. No new patches available." -ForegroundColor Green
    if ($currentVersion) {
        Write-Host "Current version: $currentVersion" -ForegroundColor White
    }
}
Write-Host "==========================================================" -ForegroundColor Cyan

# 5. Post-processing (Only runs when patches were actually applied)
if ($updateCount -gt 0) {
    $dateCode = ""
    if ($currentVersion -match "-(\d+)$") {
        $dateCode = $matches[1]
    } elseif ($currentVersion -match "(\d{8,12})") {
        $dateCode = $matches[1]
    }

    # 5-1. Update datecode in ea3-config.xml
    if (-not [string]::IsNullOrWhiteSpace($ea3ConfigPath) -and -not [string]::IsNullOrWhiteSpace($dateCode)) {
        $ea3FullPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $ea3ConfigPath))
        if (Test-Path $ea3FullPath -PathType Leaf) {
            $xmlContent = Get-Content $ea3FullPath -Raw -Encoding UTF8
            if ($xmlContent -match '<ext\s+__type="str">[^<]*</ext>') {
                $newXml = [regex]::Replace($xmlContent, '<ext\s+__type="str">[^<]*</ext>', "<ext __type=`"str`">$dateCode</ext>")
                [System.IO.File]::WriteAllText($ea3FullPath, $newXml, [System.Text.Encoding]::UTF8)
                Write-Host "`n[Post-Process] Updated ea3-config.xml (<ext __type=`"str`">$dateCode</ext>)" -ForegroundColor Green
            }
        }
    }

    # 5-2. Copy files inside modules to parent directory
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

# 6. Countdown and auto-exit
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