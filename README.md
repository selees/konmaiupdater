# KONMAI Patch Web Server & Auto Updater

An automated patch server and client updater designed for arcade machines (BEMANI / SOUND VOLTEX, etc.).
Place your patch archive files (e.g. `KFC-2026080500 to 2026082500.rar`) in the server folder, and the client will automatically detect its current version from `version.txt`, download the sequential updates, extract them directly to the game folder, update `ea3-config.xml`, and move `modules` if needed.

---

## 📁 Directory Structure

```text
konmaiupdater/
├── server/                    # [Server PC] Patch Distribution
│   ├── config.ini            # Server settings (Bind IP, Port, Client IP filter, Updates folder)
│   ├── updates/              # Drop your .rar patch files here
│   ├── server.ps1            # Lightweight native HTTP server
│   └── start_server.bat      # Double-click to start server
│
└── client/                    # [Client / Arcade Cabinet] Game Updater
    ├── config.ini            # Server URL, Game dir, XML path, Modules options
    ├── version.txt           # Current game version (auto-starts from lowest if missing)
    ├── updater.ps1           # Auto download, unpack, post-process & sequential update engine
    └── updater.bat           # Double-click to update (auto-closes in 5s when finished)
```

---

## ⚙️ Configuration Files

### 1. `server/config.ini`
```ini
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
```

### 2. `client/config.ini`
```ini
[Server]
; Web server URL (e.g. http://192.168.11.152:8080)
ServerUrl=http://192.168.11.152:8080

[Update]
; Game ID code to match patches (e.g. KFC, MDX, LDJ)
GameID=KFC

; Target game directory (. for current directory, or ./KFC for subfolder)
TargetDir=./KFC

[Ea3Config]
; Path to ea3-config.xml (relative or absolute, leave empty to disable)
; Automatically updates <ext __type="str">DATE</ext> to the latest version date
Ea3ConfigPath=./KFC/contents/prop/ea3-config.xml

[Modules]
; Copy files inside modules folder to its parent folder (true / false)
MoveModulesUp=true
; Path to modules directory (leave empty to auto-detect inside TargetDir)
ModulesDir=./KFC/contents/modules
```

---

## 🚀 How to Use

1. **Start Server (`server/start_server.bat`)**
   - Place patch archives into `server/updates/`.
   - Configure `server/config.ini` if you need custom IP binding, port, or client IP filtering.
   - Run `start_server.bat`.

2. **Run Client Updater (`client/updater.bat`)**
   - Configure `client/config.ini` with the server URL.
   - Run `updater.bat`.
   - The updater will download sequentially, unpack cleanly into the game folder, update `ea3-config.xml`, handle `modules`, and close after 5 seconds.
