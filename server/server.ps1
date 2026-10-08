param (
    [string]$ConfigFile = "$PSScriptRoot\config.ini"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$host.UI.RawUI.WindowTitle = "KONMAI Patch Web Server"

# 1. Default configuration values
$bindIp = "0.0.0.0"
$port = 8080
$allowedClientIp = "*"
$updatesDir = "$PSScriptRoot\updates"

# Load config.ini
if (Test-Path $ConfigFile) {
    Get-Content $ConfigFile -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line.StartsWith(";") -or $line.StartsWith("#")) { return }
        
        if ($line -match "^BindIP\s*=\s*(.+)$") {
            $bindIp = $matches[1].Trim()
        }
        elseif ($line -match "^Port\s*=\s*(\d+)$") {
            $port = [int]$matches[1].Trim()
        }
        elseif ($line -match "^AllowedClientIP\s*=\s*(.+)$") {
            $allowedClientIp = $matches[1].Trim()
        }
        elseif ($line -match "^UpdatesDir\s*=\s*(.+)$") {
            $val = $matches[1].Trim()
            $updatesDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $val))
        }
    }
} else {
    @"
[Network]
; Server binding IP address
; 0.0.0.0 = Listen on all network adapters
; Or specify a specific local IP (e.g. 192.168.11.152)
BindIP=0.0.0.0

; Server listening port
Port=8080

; Allowed client IP filter (Whitelist)
; * = Allow all incoming client connections
; Or specify an IP (e.g. 192.168.11.20) to only process requests from that machine
AllowedClientIP=*

[Storage]
; Directory containing .rar patch files (relative or absolute)
UpdatesDir=./updates
"@ | Set-Content -Path $ConfigFile -Encoding UTF8
}

if (-not (Test-Path $updatesDir)) {
    New-Item -ItemType Directory -Path $updatesDir -Force | Out-Null
}

# Resolve listening IP address
$ipToBind = [System.Net.IPAddress]::Any
if ($bindIp -ne "0.0.0.0" -and -not [string]::IsNullOrWhiteSpace($bindIp)) {
    try {
        $ipToBind = [System.Net.IPAddress]::Parse($bindIp)
    } catch {
        Write-Host "[ERROR] Invalid BindIP in config.ini: $bindIp" -ForegroundColor Red
        Write-Host "Falling back to 0.0.0.0 (All interfaces)." -ForegroundColor Yellow
        $ipToBind = [System.Net.IPAddress]::Any
        $bindIp = "0.0.0.0"
    }
}

# Display Banner
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "                 KONMAI Patch Web Server                  " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Bind IP          : $bindIp" -ForegroundColor Gray
Write-Host "Server Port      : $port" -ForegroundColor Gray
Write-Host "Allowed Client IP: $allowedClientIp" -ForegroundColor Gray
Write-Host "Patch Folder     : $updatesDir" -ForegroundColor Gray
Write-Host ""

# Display available URLs for client
Write-Host "[ Available URLs for client config.ini ]" -ForegroundColor Green
if ($bindIp -eq "0.0.0.0") {
    $localIps = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { 
        $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -notlike '169.*' 
    } | Select-Object -ExpandProperty IPAddress

    foreach ($ip in $localIps) {
        Write-Host "  -> http://$($ip):$port" -ForegroundColor White
    }
    Write-Host "  -> http://localhost:$port (Local test)" -ForegroundColor DarkGray
} else {
    Write-Host "  -> http://$($bindIp):$port" -ForegroundColor White
}
Write-Host "==========================================================" -ForegroundColor Cyan

# GitHub sync for client updater (updater.ps1)
function Sync-ClientUpdaterFromGitHub {
    $githubUrl = "https://raw.githubusercontent.com/selees/konmaiupdater/main/client/updater.ps1"
    
    # Target file: prefer repo client folder if exists, otherwise server folder
    $repoClientDir = Join-Path (Split-Path -Parent $PSScriptRoot) "client"
    $targetFile = if (Test-Path $repoClientDir -PathType Container) {
        Join-Path $repoClientDir "updater.ps1"
    } else {
        Join-Path $PSScriptRoot "updater.ps1"
    }

    $localVersion = [version]"0.0.0"
    if (Test-Path $targetFile -PathType Leaf) {
        $localContent = Get-Content $targetFile -Raw -Encoding UTF8
        if ($localContent -match '#\s*ScriptVersion:\s*([0-9\.]+)') {
            try { $localVersion = [version]$matches[1] } catch {}
        }
    }

    Write-Host "[GitHub Sync] Checking for latest client updater (Local: v$localVersion)..." -ForegroundColor Gray
    try {
        $remoteContent = & curl.exe -fsSL --connect-timeout 3 --max-time 6 "$githubUrl" 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($remoteContent)) {
            $remoteVersion = [version]"0.0.0"
            if ($remoteContent -match '#\s*ScriptVersion:\s*([0-9\.]+)') {
                try { $remoteVersion = [version]$matches[1] } catch {}
            }

            if ($remoteVersion -gt $localVersion -or (-not (Test-Path $targetFile -PathType Leaf))) {
                [System.IO.File]::WriteAllText($targetFile, $remoteContent, [System.Text.Encoding]::UTF8)
                Write-Host "[GitHub Sync] Updated client updater to v$remoteVersion from GitHub!" -ForegroundColor Green
            } else {
                Write-Host "[GitHub Sync] Client updater is already up to date (v$localVersion)." -ForegroundColor Gray
            }
        } else {
            Write-Host "[GitHub Sync] Could not reach GitHub (offline/timeout). Using local files." -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "[GitHub Sync] Offline or connection error. Using local files." -ForegroundColor DarkGray
    }
}

Sync-ClientUpdaterFromGitHub

# Start TcpListener
$listener = [System.Net.Sockets.TcpListener]::new($ipToBind, $port)
try {
    $listener.Start()
} catch {
    Write-Host "`n[ERROR] Failed to start server on $($bindIp):$($port) !" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "Please check if the port is already in use or if you have permission to bind to that IP.`n" -ForegroundColor DarkGray
    pause
    exit 1
}

Write-Host "Server is running! (Press Ctrl + C to stop)`n" -ForegroundColor Green

# Parse allowed client IP whitelist (comma-separated support)
$allowedList = @()
if ($allowedClientIp -ne "*" -and -not [string]::IsNullOrWhiteSpace($allowedClientIp)) {
    $allowedList = $allowedClientIp.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
}

try {
    while ($true) {
        $tcpClient = $listener.AcceptTcpClient()
        $clientEndPoint = $tcpClient.Client.RemoteEndPoint -as [System.Net.IPEndPoint]
        $clientIp = if ($clientEndPoint) { $clientEndPoint.Address.ToString() } else { "Unknown" }
        $stream = $tcpClient.GetStream()
        
        try {
            # Check client IP whitelist
            if ($allowedList.Count -gt 0 -and ($allowedList -notcontains $clientIp) -and ($clientIp -ne "127.0.0.1") -and ($clientIp -ne "::1")) {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [BLOCKED] Rejected request from unauthorized client IP: $clientIp" -ForegroundColor Red
                $stream.Close()
                $tcpClient.Close()
                continue
            }

            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII)
            $requestLine = $reader.ReadLine()
            
            if (-not [string]::IsNullOrWhiteSpace($requestLine)) {
                $parts = $requestLine.Split(' ')
                if ($parts.Length -ge 2) {
                    $method = $parts[0]
                    $rawUrl = $parts[1]

                    # URL decode
                    $decodedUrl = [System.Uri]::UnescapeDataString($rawUrl)
                    $cleanPath = $decodedUrl.TrimStart('/')

                    # 1. File list request (/list or /)
                    if ($cleanPath -eq "list" -or $cleanPath -eq "") {
                        $files = Get-ChildItem -Path $updatesDir -File -Filter "*.rar" | Select-Object -ExpandProperty Name
                        $responseBody = ($files -join "`n")
                        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
                        
                        $header = "HTTP/1.1 200 OK`r`n" +
                                  "Content-Type: text/plain; charset=utf-8`r`n" +
                                  "Content-Length: $($bodyBytes.Length)`r`n" +
                                  "Connection: close`r`n`r`n"
                        $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
                        $stream.Write($headerBytes, 0, $headerBytes.Length)
                        if ($method -ne "HEAD") {
                            $stream.Write($bodyBytes, 0, $bodyBytes.Length)
                        }
                        $stream.Flush()
                        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$clientIp] List requested (/list) -> $($files.Count) file(s)" -ForegroundColor Gray
                    }
                    # 2. File download request
                    else {
                        $fileName = [System.IO.Path]::GetFileName($cleanPath)
                        $filePath = ""

                        # Search candidate locations: updates folder -> client folder -> server folder
                        $candidatePaths = @(
                            (Join-Path $updatesDir $fileName),
                            (Join-Path (Split-Path -Parent $PSScriptRoot) "client\$fileName"),
                            (Join-Path $PSScriptRoot $fileName)
                        )
                        foreach ($c in $candidatePaths) {
                            if (Test-Path $c -PathType Leaf) {
                                $filePath = $c
                                break
                            }
                        }

                        # If updater script was requested but not found locally, try downloading from GitHub on-demand
                        if (-not $filePath -and ($fileName -eq "updater.ps1" -or $fileName -eq "updater.bat")) {
                            Sync-ClientUpdaterFromGitHub
                            foreach ($c in $candidatePaths) {
                                if (Test-Path $c -PathType Leaf) {
                                    $filePath = $c
                                    break
                                }
                            }
                        }

                        if (Test-Path $filePath -PathType Leaf) {
                            $fileInfo = [System.IO.FileInfo]::new($filePath)
                            $fileSize = $fileInfo.Length
                            $fileSizeMB = [Math]::Round($fileSize / 1MB, 2)

                            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$clientIp] Download started: $fileName ($fileSizeMB MB)" -ForegroundColor Yellow
                            
                            $header = "HTTP/1.1 200 OK`r`n" +
                                      "Content-Type: application/octet-stream`r`n" +
                                      "Content-Disposition: attachment; filename=`"$fileName`"`r`n" +
                                      "Content-Length: $fileSize`r`n" +
                                      "Connection: close`r`n`r`n"
                            $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
                            $stream.Write($headerBytes, 0, $headerBytes.Length)

                            if ($method -ne "HEAD") {
                                $fileStream = [System.IO.File]::OpenRead($filePath)
                                $buffer = New-Object byte[] 65536
                                while (($bytesRead = $fileStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                                    $stream.Write($buffer, 0, $bytesRead)
                                }
                                $fileStream.Close()
                                $stream.Flush()
                            }
                            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$clientIp] Download completed: $fileName" -ForegroundColor Green
                        } else {
                            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$clientIp] 404 Not Found: $fileName" -ForegroundColor Red
                            $notFoundBody = "404 Not Found"
                            $bodyBytes = [System.Text.Encoding]::ASCII.GetBytes($notFoundBody)
                            $header = "HTTP/1.1 404 Not Found`r`n" +
                                      "Content-Length: $($bodyBytes.Length)`r`n" +
                                      "Connection: close`r`n`r`n"
                            $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
                            $stream.Write($headerBytes, 0, $headerBytes.Length)
                            $stream.Write($bodyBytes, 0, $bodyBytes.Length)
                            $stream.Flush()
                        }
                    }
                }
            }
        } catch {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Connection error: $($_.Exception.Message)" -ForegroundColor DarkGray
        } finally {
            $stream.Close()
            $tcpClient.Close()
        }
    }
} finally {
    $listener.Stop()
}