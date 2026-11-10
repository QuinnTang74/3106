<p align="center">
  <img src="docs/images/app-icon.png" width="120" alt="3106">
</p>

<h1 align="center">3106</h1>

<p align="center">
  A no-jailbreak iOS container manager: app data, patches, cleaning, wallpapers, and dialer themes.
</p>

<p align="center">
  <a href="README.md">简体中文</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="docs/PATCH_GUIDE.md">Patch guide</a>
</p>

## Project

| Item | Value |
| --- | --- |
| Version | **3.1.12** (stable) |
| Current release | **v3.1.12** (build 16, wallpaper import/scan, update prompt and tab-switch performance) |
| Supported systems | iOS 17.0–18.7.1 · 26.0–26.7.2 · 27.0–27.3 beta 1 |
| Access backend | kernel / `bad_query` / `worse_query` |
| UI languages | Simplified Chinese · English · Vietnamese |
| Signing | iOS 26.7+ / 27.x requires an App Group entitlement |
| Bundle ID | `com.qingtang.3106` |
| Repository | <https://github.com/QuinnTang74/3106.git> |

## Features

| Module | Description |
| --- | --- |
| App data browser | App containers, App Groups, extension data, internal daemons; iOS 27 can list System Data and some System Groups |
| Patch manager | Exports `.3106`, imports legacy `.3105`; multi-target, user inputs, optional password, rollback |
| Cleaner | Per-app `Library/Caches` and `tmp` cleanup, including safe deletion through symlinked Caches inside the container |
| Wallpapers and themes | `.tendies` PosterBoard wallpapers and `.3105pass` dialer themes |
| Configurable tab bar | Toggle tab items in Settings, up to five slots, Home fixed; Developer Mode on by default |
| Localization | Simplified Chinese, English, Vietnamese |

## Recent changes

| Version | Highlights |
| --- | --- |
| **3.1.12** | Stable: wallpaper import/scan, update prompt, and Cleaner-to-Files stutter fixes; includes all 3.1.8–3.1.11 fixes |
| **3.1.11** | Test build: collect descriptors from the same successful tree enumeration; add import stage logs and a launch version banner |
| **3.1.10** | Test build: fix `isContained` `/var` vs `/private/var` after `.tendies` extraction; find device descriptors with an enumerator first |
| **3.1.9** | Test build: force `/private/var` for wallpaper scans; ZIP GB18030 names, backslash paths, duplicate dirs and 768 MB video entries; reuse LS/filesystem caches and skip redundant MHA scanning |
| **3.1.8** | Fix update prompt on the latest build, cleaner freeze when switching tabs, wallpaper `/var` path scan, and add import error details |
| **3.1.7** | Wallpaper: fix iOS 27.3 layout scan, Mercury folder names, video descriptor mapping, loose descriptor packages; cleaner updates per app with a loaded count |
| **3.1.6** | Folder favorites: long-press to favorite, favorite paths listed inline at the top of the file tab page, compatible with 3105 2.0 data |
| **3.1.5** | App data browser shows every container again: MHA guard removed, LaunchServices `bdsl` parser, unidentified containers in a read-only section |
| **3.1.4-r2** | Project URL moved to **QuinnTang74/3106**; in-app GitHub link, update checker, and README updated |
| **3.1.4** | Cleaner deletion uses the scanned container path; `FileManager` removal refuses symlinks escaping the container |
| 3.1.3 | Wallpaper scanner supports nested/non-standard iOS 27.3 PosterBoard layouts and creates required descriptors directories |
| 3.1.2 | Cleaner measurement via `FileManager`; PosterBoard resolved by scanning the poster store; Settings gear always visible on Cleaner |
| 3.1.1 | Filesystem app enumeration and container-index fallback; per-path grants for wallpaper scan/probe/install/reset |
| 3.1.0 | Configurable tab bar, Developer Mode default on, promotion/credits removed, Chinese-first README |

See [CHANGELOG.md](CHANGELOG.md) for the full history.

## Compatibility

| System | Verified range | Backend |
| --- | --- | --- |
| iOS 17 | 17.0–17.7.x | kernel chain |
| iOS 18 | 18.0–18.7.1 | kernel chain |
| iOS 26 | 26.0–26.6.1 | `bad_query` |
| iOS 26 | 26.7–26.7.2 | `worse_query` |
| iOS 27 | 27.0–27.2 | `worse_query` |
| iOS 27 | 27.3 beta 1 (`24C5037i`) | `worse_query` (experimental) |

> iOS 17/18 still uses the manual kernel chain; iOS 26/27 does not use a kernel exploit. System Data is listing-only on iOS 27.

## Installation and signing

| Signing method | App Group | Notes |
| --- | --- | --- |
| AltStore / SideStore / Sideloadly with an Apple ID | Created automatically | Recommended; a free Apple ID works |
| Own developer account | Explicit App ID with App Groups | Create a dedicated profile |
| Certificate (`.p12`) + wildcard profile | Not supported | `worse_query` reports “No App Group” |
| LiveContainer | Depends on the signing environment | Check **Settings → App Group** |

With a certificate and provisioning profile, the profile must be an explicit App ID with the **App Groups** capability. Wildcard profiles cannot carry an App Group.

## Build and test

| Task | Command |
| --- | --- |
| Unsigned build | `xcodebuild -project ThreeOneOSSix.xcodeproj -scheme 3106 -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build` |
| Policy tests | `bash Tests/run_policy_tests.sh` |
| Output | `dist/`, this release is `3106-3.1.12-unsigned.ipa` |

## Download

Stable releases are published on GitHub Releases:

<https://github.com/QuinnTang74/3106/releases>

The release asset is an unsigned IPA; sign it with one of the methods above before installing.

Current asset: `3106-3.1.12-unsigned.ipa` (SHA256 `788fafd2814aaa626d474f07e1dc3369ff3e2320eaf95a3368d274f03f9a56cf`).

## License and commercial use

This repository is distributed under the **GNU GPL v3.0**; the full text is in [LICENSE](LICENSE).

The project contains GPL-3.0 code from 3105, `worse_query`, WQ Files, and others. GPL-3.0 does not permit an additional “non-commercial” restriction, so the combined work cannot be relicensed as a strictly non-commercial project.

The author does not want this project used commercially. For commercial use, please contact the repository author first. This sentence states the author's preference; it is not an additional restriction on GPL-3.0 and does not change the licenses of upstream or third-party code.

When modifying or redistributing, you must keep the copyright, origin, and license notices in [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md), and state what you changed. This is required by GPL-3.0 and by this project.

## Reference

This project references and is based on the **3105 project** (original author YangJiii) 2.0 source; the iOS 27 adaptation, `worse_query` port, cleaner and wallpaper fixes, and the 3106 rename were built on top of it. Third-party copyright and origin notices are in [NOTICE.md](NOTICE.md) (required by GPL-3.0, not promotional content).