# KONMAI Patch Web Server & Auto Updater

An automated patch server and client updater designed for arcade machines (BEMANI / SOUND VOLTEX, etc.).
Place your patch archive files (e.g. `KFC-2026080500 to 2026082500.rar`) in the server folder, and the client will automatically detect its current version from `bootstrap.xml`, download sequential updates, extract them directly to the game folder, update `ea3-config.xml`, move `modules`, and apply DLL binary patches via [sp2xpatcher](https://github.com/eamuse/sp2xpatcher) integration.

---

## 📁 Directory Structure

```text
konmaiupdater/
├── server/                    # [Server PC] Patch Distribution
│   ├── client_updater.ps1    # Client updater script distributed to cabinets
│   ├── config.ini            # Server settings (Bind IP, Port, Client IP filter, Updates folder)
│   ├── updates/              # Drop your .rar patch files here
│   ├── server.ps1            # Lightweight native HTTP server
│   └── start_server.bat      # Double-click to start server
│
└── client/                    # [Client / Arcade Cabinet] Game Updater
    ├── config.ini            # Server URL, Game dir, Modules & sp2xpatcher options
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

[Modules]
; Copy files inside modules folder to its parent folder (true / false)
MoveModulesUp=true
; Path to modules directory (leave empty to auto-detect inside TargetDir)
ModulesDir=./KFC/contents/modules

[Patches]
; Enable automatic DLL patching via sp2xpatcher (true / false)
EnableSp2xPatcher=true
; List of patches to apply (comma-separated).
; For memory patches: Patch Name
; For union patches: Patch Name:Option Name
; Example:
; EnabledPatches=Standard/Menu Timer Freeze, Premium Free Timer Freeze, Game FPS Target:120 FPS
EnabledPatches=Standard/Menu Timer Freeze, Game FPS Target:120 FPS
```

> [!NOTE]
> `bootstrap.xml` (game version detection) and `ea3-config.xml` (datecode update) are automatically discovered inside `TargetDir` (e.g. in `contents/prop/` or `prop/`).

---

## 🎮 sp2xpatcher Integration (Automated DLL Patching)

The client updater includes native integration with [eamuse/sp2xpatcher](https://github.com/eamuse/sp2xpatcher) to automate game DLL hex patching (e.g. `soundvoltex.dll`, `bm2dx.dll`, etc.).

### Key Features:
1. **Automatic Version Matching**:
   - Matches the game's `GameID` and release date code from `bootstrap.xml` against `SUPPORTED.md`.
   - Downloads the corresponding patch definition JSON file and caches it locally under `client/patches/` (supporting offline operation).
2. **Safe Binary Patching**:
   - Automatically creates a `.bak` backup file (e.g. `soundvoltex.dll.bak`) before making any first modifications.
   - Verifies target bytes before writing to prevent file corruption.
   - Idempotent: checks if a patch is already applied; running the updater again is completely safe and skips already applied patches.
3. **Patch Discovery**:
   - Set `EnableSp2xPatcher=true` and leave `EnabledPatches=` empty in `client/config.ini`.
   - Run `updater.bat` to list all available patches and union options for your exact game version in the console, ready to copy & paste into `EnabledPatches`.

---

## 🚀 How to Use

1. **Start Server (`server/start_server.bat`)**
   - Place patch archives into `server/updates/`.
   - Configure `server/config.ini` if you need custom IP binding, port, or client IP filtering.
   - Run `start_server.bat`.

2. **Run Client Updater (`client/updater.bat`)**
   - Configure `client/config.ini` with the server URL and desired options.
   - Run `updater.bat`.
   - `updater.bat` automatically checks and updates `updater.ps1` from the server before launching (skips silently if server is offline).
   - The updater will download sequentially, unpack cleanly into the game folder, update `ea3-config.xml`, handle `modules`, apply `sp2xpatcher` DLL patches, and close after 5 seconds.
