# KONMAI Patch Web Server & Auto Updater

An automated patch server and client updater designed for arcade machines (BEMANI / SOUND VOLTEX, etc.).
Place your patch archive files (e.g. `KFC-2026080500 to 2026082500.rar`) in the server folder, and the client will automatically detect its current version from `bootstrap.xml`, inspect any existing patches applied on the current game DLL, download sequential updates, extract them directly to the game folder, update `ea3-config.xml`, move `modules`, and re-apply DLL binary patches via [sp2xpatcher](https://github.com/eamuse/sp2xpatcher) integration.

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
; Automatically populated from existing patched DLLs before update, or specify manually.
; For memory patches: Patch Name
; For union patches: Patch Name:Option Name
; Example:
; EnabledPatches=Standard/Menu Timer Freeze, Premium Free Timer Freeze, Game FPS Target:120 FPS
EnabledPatches=
```

> [!NOTE]
> - **Non-destructive `config.ini` Migration**: When `updater.ps1` is auto-updated from an older version, it preserves your existing `config.ini` settings and comments, and only appends newly introduced or missing options.
> - `bootstrap.xml` (game version detection) and `ea3-config.xml` (datecode update) are automatically discovered inside `TargetDir` (e.g. in `contents/prop/` or `prop/`).

---

## 🎮 sp2xpatcher Integration (Automated DLL Patching)

The client updater includes native integration with [eamuse/sp2xpatcher](https://github.com/eamuse/sp2xpatcher) to automate game DLL hex patching (e.g. `soundvoltex.dll`, `bm2dx.dll`, etc.).

### Key Features:
1. **Automatic Pre-Update Patch Detection & Migration**:
   - Before applying game updates, the updater inspects your current game version and existing DLL against `sp2xpatcher` definitions to detect which patches (both `memory` and non-default `union` options) are already applied.
   - Any detected patches are automatically added and saved to `EnabledPatches` in `client/config.ini`, then re-applied to the newly updated DLL at the new version's offsets after the update completes.
2. **Automatic Version Matching**:
   - Matches the game's `GameID` and release date code from `bootstrap.xml` against `SUPPORTED.md`.
   - Downloads the corresponding patch definition JSON file and caches it locally under `client/patches/` (supporting offline operation).
3. **Safe Binary Patching**:
   - Automatically creates/updates a clean `.bak` backup file (e.g. `soundvoltex.dll.bak`) before modifying the DLL.
   - Verifies target bytes before writing to prevent file corruption.
   - Idempotent: checks if a patch is already applied; running the updater again is completely safe and skips already applied patches.
4. **Patch Discovery**:
   - If the DLL has no patches applied yet and `EnabledPatches=` is empty in `client/config.ini`, running `updater.bat` lists all available patches and union options for your exact game version in the console.

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
   - The updater will detect any existing DLL patches, download sequential updates, unpack cleanly into the game folder, update `ea3-config.xml`, handle `modules`, re-apply `sp2xpatcher` DLL patches, and close after 5 seconds.
