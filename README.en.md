# SwitchNetwork

[简体中文](README.md) | **English**

A small macOS tool for switching network configurations per scenario.

Save a set of "IP / netmask / gateway / DNS / static routes" as a **profile**, have it applied automatically when you plug in an Ethernet cable, or switch with one click. When you don't need it, hand the interface back to the system in one click (back to DHCP, DNS via DHCP, and remove the static routes this app added).

## Screenshots

**Interfaces** — the current IP, gateway, DNS, and configuration method of every interface, whether the link is up, and whether the active profile was applied automatically.

![Interfaces](docs/screenshots/overview.png)

| **Network Service Priority** | **Profiles** |
|---|---|
| ![Network Service Priority](docs/screenshots/service-priority.png) | ![Profiles](docs/screenshots/profiles.png) |
| **Automation** | **Settings** |
| ![Automation](docs/screenshots/automation.png) | ![Settings](docs/screenshots/settings.png) |

## Features

- **Interfaces** — lists every network interface with its current IP, gateway, DNS, and configuration method, so you can see at a glance which link is up and whether the active profile was applied automatically.
- **Profiles** — a profile holds a manual IP or DHCP, DNS servers, any number of static routes (destination network + next hop), and whether applying it should move that network service to the front of the service order.
- **Automation** — applies the matching profile when an interface is plugged in or Wi-Fi joins a network (debounced, so link flapping doesn't cause repeated writes). Automatic apply only fires when the interface is connected.
- **Hand back to the system** — applies no profile and returns the interface to macOS: static routes are removed first, then DHCP is restored (route next hops still live in the old subnet, so doing it in the other order blackholes traffic for a while), and DNS goes back to automatic.
- **Network service priority** — manage macOS's "service order" directly; the system uses it to decide which link carries traffic.
- **Trash** — deleted profiles go to the trash first and are kept for 30 days by default, and can be restored during that window. Expired or unwanted ones can be deleted permanently right away.
- **iCloud sync** — profiles and the trash live in iCloud Drive and sync across your Macs; on a machine without iCloud the app falls back to a local folder automatically.
- **In-app update check** — checks once at launch and whenever you ask. A new version can be downloaded and installed in place; the previous version is kept as a backup for one-click rollback.
- **Chinese and English UI** — follows the system language, or pin one in Settings. Light / dark / follow system.

## Requirements

- macOS 11 Big Sur or newer (universal binary — runs on both Intel and Apple silicon)
- Changing IP addresses and routes needs administrator rights. On first use, click **Install Authorization** under Settings → Permissions. It writes one rule into `/etc/sudoers.d/` that **only allows the `networksetup` and `route` commands**, so you aren't prompted for a password on every plug/unplug or restart.

## Installation

1. Download the latest `SwitchNetwork-<version>.dmg` from [Releases](https://github.com/cat-clever/SwitchNetwork/releases)
2. Open the dmg and either:
   - drag `SwitchNetwork.app` into Applications, **or**
   - double-click `安装 SwitchNetwork（双击运行）.command` inside the image — it asks once and installs the app, clearing the quarantine attribute along the way (it asks for your login password; it uses the system's own `xattr` command)
3. If the first launch says the developer cannot be verified: right-click (or Control-click) the app → Open → click **Open** again in the dialog. This is needed only once.

> The app has no Apple Developer signature (a personal tool; buying a certificate isn't planned), which is why the step above exists. You can also just build it yourself — see below.

## Usage

The main window has four sections: **Interfaces / Profiles / Automation / Settings**.

The fields in a profile:

| Field | Meaning |
|---|---|
| Interface | Which network interface it binds to (`en0`, `en1`, …) |
| IP mode | A manual IP/netmask/gateway, or DHCP |
| DNS | A manual list of servers, or automatic |
| Static routes | Destination network + next hop, written one by one when the profile is applied |
| Move to front | Move this network service to the top of the service order when the profile is applied |

Some operations need administrator rights. When they fail, the result of every step (success / notice / failure) is shown on the Interfaces page, and the full record is in the log.

## Where Data Lives

| Content | Location |
|---|---|
| Profiles, trash | With iCloud: `~/Library/Mobile Documents/com~apple~CloudDocs/SwitchNetwork/`<br>Without: `~/Library/Application Support/SwitchNetwork/` |
| Settings | `~/Library/Application Support/SwitchNetwork/settings.json` (always local) |
| Log | `~/Library/Logs/SwitchNetwork.log` |

Settings deliberately **do not** follow iCloud: they contain things bound to this particular machine, like launch at login, the Dock icon, and the network service order — syncing those to another Mac only causes confusion.

All files are plain JSON, so you can edit them by hand or copy them out as a backup. One caveat with iCloud: if another machine hasn't downloaded the file yet (macOS evicts files to save space, leaving a placeholder), the app **pauses writing** and tells you, so a real cloud profile is never overwritten with an empty one. If you see that notice, go online, wait a moment, and reopen the app.

## Updates

The app checks for a new version at launch (a single GET to GitHub's releases API) and you can also check manually in Settings.

When a new version exists, click **Download and Install**: download the dmg → verify the SHA256 → verify the version and signature of the app inside the image → install it into Applications → restart. The previous version is kept as a backup, so you can **roll back** from Settings if something goes wrong.

A few notes:

- The app only replaces itself when it runs from `/Applications`. Running straight from Xcode (where the build lands in DerivedData) only offers to open the release page.
- On macOS 13 and later, the first replacement may trigger the system's "SwitchNetwork wants to modify other apps" prompt. Allow it once; if you decline, the app falls back to telling you to install the dmg manually.
- Manual installation always works too: download a new dmg and install over the old one. Your profiles are not lost.

## Building from Source

You need Xcode (the command line tools alone are not enough — a full Xcode.app is required).

```bash
git clone https://github.com/cat-clever/SwitchNetwork.git
cd SwitchNetwork
open SwitchNetwork.xcodeproj      # or build from the command line:
xcodebuild -project SwitchNetwork.xcodeproj -scheme SwitchNetwork \
    -configuration Debug -destination 'platform=macOS' build
```

To build a dmg:

```bash
./make_dmg.sh                     # Release by default; produces SwitchNetwork-<version>.dmg
./make_dmg.sh Debug               # a Debug build
```

`make_dmg.sh` does the build, reads the version, and assembles the image in one go. The dmg contains the app, the install script, and a symlink to Applications. The script finds `xcodebuild` itself; if the selected developer directory isn't Xcode it falls back to `/Applications/Xcode.app`, so you don't need to run `sudo xcode-select` first.

## Releasing

The version number lives in exactly **one** file: `Config/SwitchNetwork.xcconfig`.

```
MARKETING_VERSION = 0.0.2
CURRENT_PROJECT_VERSION = 2
SWITCHNETWORK_GITHUB_REPO = cat-clever/SwitchNetwork
```

Change `MARKETING_VERSION` and push to `main`, and the GitHub Action will: build → assert the version inside the built app matches the config → package the dmg → compute the SHA256 → tag `v<version>` and publish a Release (with the dmg and its `.sha256` attached). Nothing is built at all unless the version changed — a push that keeps the same version only runs the cheap check.

- Each version is released once. If the tag already exists the build is skipped, so pushing again is harmless; to re-release, delete the Release and tag on GitHub or bump the version.
- Don't change the version in Xcode's "Versioning" section — that writes the value back into `project.pbxproj` and overrides the xcconfig (the version assertion in the workflow guards against exactly this and fails the build if it happens).

## FAQ

**"Cannot verify the developer" or "is damaged" when opening**
Right-click → Open. If it says "is damaged", the quarantine attribute is still there — run the install script inside the dmg once, or do it by hand:

```bash
sudo xattr -rd com.apple.quarantine /Applications/SwitchNetwork.app
```

**I changed a profile but nothing happened**
Look at the result card for that operation on the Interfaces page: a write failure is usually a permissions problem (install the authorization under Settings → Permissions); if the interface is not connected, the profile is written out first and takes effect once it connects.

**After "don't use a profile" it went back to the old configuration**
Automatic apply writes it back. Handing the interface back to the system turns off automatic apply for every profile on that interface; if your setup still needs it, just turn it back on.

**I can't see my profiles in iCloud**
First check that System Settings → Apple Account → iCloud → iCloud Drive is on. If it isn't, the app uses the local folder automatically — everything works the same, it just doesn't sync.

**Private repository**
If the repository is private, the in-app update check cannot read release information (GitHub requires a login) and falls back to offering the release page.

## Repository Layout

```
Config/                     Version and repository slug (the only config you edit)
  SwitchNetwork.xcconfig
  Info.plist                Holds one custom key: the repository slug
SwitchNetwork/              Source
  Models/                   Data models: profiles, settings, interface status
  Network/                  Reads and writes system network state (networksetup / route / scutil / sudoers)
  Store/                    JSON persistence (iCloud / local folder, three-state reads)
  Support/                  Logging, shell wrapper, version and updates
  UI/                       SwiftUI interface
  Localization/             Chinese and English string tables
docs/screenshots/           Screenshots used in the READMEs
make_dmg.sh                 Builds the dmg
安装 SwitchNetwork（双击运行）.command
.github/workflows/release.yml
README.md / README.en.md    Chinese / English docs
```

## Privacy

- No network access except the update check — a single GET to GitHub's releases API, plus fetching the dmg from the Release assets when you install an update.
- Nothing is uploaded: no analytics, no crash reporting, no account.
- Network configuration is written only into the local system (`networksetup` / `route`). After you delete the app, any IP, DNS, or static routes already written into the system are not undone automatically — use "hand back to the system" in the app first if you want that.

## License

[GPL-3.0](LICENSE).
