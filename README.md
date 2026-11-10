<p align="center">
  <img src="docs/images/app-icon.png" width="132" alt="3106 app icon">
</p>

<h1 align="center">3106</h1>

<p align="center">
  An iOS content hub and manager for patches, app data, dialer themes, and PosterBoard wallpapers.
</p>

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-3.0-E6753A?style=flat-square">
  <img alt="iOS" src="https://img.shields.io/badge/iOS-17.0–18.7.1%20%7C%2026.0–26.7.2%20%7C%2027.0–27.2-222222?style=flat-square">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="Languages" src="https://img.shields.io/badge/languages-English%20%7C%20Tiếng%20Việt%20%7C%20简体中文-E6753A?style=flat-square">
</p>

<p align="center">
  <a href="README.vi.md">Tiếng Việt</a> ·
  <a href="docs/PATCH_GUIDE.md">Patch guide</a> ·
  <a href="#compatibility">Compatibility</a> ·
  <a href="#license">License</a>
</p>

> [!WARNING]
> 3106 is research software for personal device management. Keep a backup and use it only on devices and data you own. Simulator screenshots demonstrate UI only; they do not verify device-level access.

## What's new in 3.0

- **iOS 27 container access through `worse_query`** — 3106 replaces the obsolete `bad_query` path on iOS 26.7–26.7.2 and iOS 27.0–27.2 with the `worse_query` sandbox escape by Taj C (forcequitOS). No kernel exploit is involved on these versions.
- **Hybrid backend** — iOS 26.0–26.6.1 keeps `bad_query` (it still reaches System Data there); iOS 26.7+ and 27.x use `worse_query` automatically.
- **App Group signing** — `worse_query` requires an App Group entitlement. AltStore, SideStore, and Sideloadly create one automatically with a free Apple ID; wildcard certificate profiles cannot carry it.
- **iOS 27.2 identity fallback** — when the container identifier xattr and metadata plist are unreadable, 3106 maps containers through `container_query_iterate_results_sync` and the LaunchServices database.
- **Renamed to 3106** — new product name, `com.qingtang.3106` bundle identifier, `threeoneossix` URL scheme, and a new `.3106` patch extension. Existing `.3105` patch packages remain importable and keep decrypting with the unchanged `3105PATCH` format magic.

## Highlights

- **Repository marketplace** — browse multiple sources and install supported content directly in 3106.
- **Installed library** — keep patches, wallpapers, dialer themes, and 3106 features together with clear type labels and package icons.
- **Application and App Group browser** — locate app data by a recognizable app name or stable identifier.
- **File operations** — search, preview, share, import, copy, move, rename, delete, create and extract ZIP archives, use tabs, and save favorites.
- **Portable patches** — target multiple apps or App Groups, expose user choices, use optional passwords, and restore original files after use. New exports use `.3106`; legacy `.3105` packages still import.
- **Additional packages** — install `.3105pass` dialer themes, `.tendies` wallpapers, and built-in 3106 features.
- **No jailbreak installation** — 3106 does not install a persistent jailbreak, bootstrap, or daemon and does not inject code into third-party apps. On iOS 26/27 it obtains sandbox extensions for containers; it does not gain root or kernel access. Because it can modify app data, no universal guarantee can be made against every app's integrity or jailbreak-detection policy.
- **Localized interface** — English, Vietnamese, and Simplified Chinese.

## Compatibility

3106 enables device-level features only for builds explicitly verified by the project:

| System | Verified range | Backend |
| --- | --- | --- |
| iOS 17 | 17.0 through 17.7.x | kernel exploit (opt-in) |
| iOS 18 | 18.0 through 18.7.1 | kernel exploit (opt-in) |
| iOS 26 | 26.0 through 26.6.1 | `bad_query` |
| iOS 26 | 26.7 through 26.7.2 | `worse_query` |
| iOS 27 | 27.0 through 27.2 | `worse_query` |
| iOS 27.3 beta 1 | experimental | `worse_query` (unverified) |

The iOS 17–18 kernel exploit is opt-in (manual button) because a failed exploit attempt may restart the app. On iOS 26/27 there is no kernel exploit: container access is a sandbox extension, and the app reports the active backend in Settings.

## Installation notes

- **iOS 26.7+ and iOS 27 need an App Group.** Sign with AltStore, SideStore, or Sideloadly using your Apple ID (free or paid) — they create the App Group automatically. With Feather, ESign, or similar certificate tools, the provisioning profile must be an explicit App ID with the App Groups capability; wildcard profiles fail with an entitlement error.
- **Bundle identifier:** `com.qingtang.3106`. The former `com.apple.mobile.MobileHouseArrest` spoof was tied to the MHA-C2 workflow and cannot be registered with an App Group; 3106 no longer uses that workflow on iOS 26/27.
- **iOS 17/18:** the kernel exploit chain is unchanged. A kernel-capable device does not need `worse_query`, but the App Group entitlement is harmless.
- The source tree does not contain certificates, provisioning profiles, signed applications, or IPA files; release assets may provide an unsigned IPA.

## Project layout

```text
3106/
├── ThreeOneOSSix/          # SwiftUI app, helpers, native bridges, localizations
├── ThreeOneOSSix.xcodeproj # Xcode project and 3106 scheme
└── docs/images/            # Repository artwork and current UI previews
```

## Security and responsible use

Do not publish logs, app containers, cookies, account databases, or patch payloads containing personal data. Report security-sensitive issues privately to the maintainer.

## Credits

3106 is a fork of [3105](https://github.com/YangJiiii/3105), developed and designed by [YangJiii](https://x.com/duongduong0908). The 3106 rename and iOS 27 backend were added on top of the upstream 2.0 source.

`worse_query` sandbox escape by Taj C ([forcequitOS](https://github.com/forcequitOS/worse_query), GPL-3.0-or-later). Product-level safety work — Caches swap recovery, grant caching, container identifier fallback — is adapted from [WQ Files](https://github.com/kolbicz/WQFiles) by Christoph Kolbicz (GPL-3.0-or-later).

Special thanks to [0xjohnny](https://x.com/0xjohnny) for [FilzaSlop](https://github.com/0xjohnnydev/FilzaSlop) and related research:

- [MobileHouseArrest-PoC](https://github.com/0xjohnnydev/MobileHouseArrest-PoC) — ContainerManager identity-trust bug
- [Geod-MCM-PoC](https://github.com/0xjohnnydev/Geod-MCM-PoC) — `geod` MobileContainerManager `partDomain` traversal
- [InstallCoordination-PoC](https://github.com/0xjohnnydev/InstallCoordination-PoC) — persisted-state and final-symlink chain
- [CFPrefsZeroFile-PoC](https://github.com/0xjohnnydev/CFPrefsZeroFile-PoC) — `cfprefsd` zero-file creation

The project also builds on work from Pocket Poster/Nugget, CrazyMind90, forcequitOS, Dopamine, and their contributors. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for full attribution and upstream links.

## License

Original portions of 3105/3106 are distributed under the [GNU General Public License v3.0](LICENSE). Third-party components remain subject to their respective upstream copyright and license terms; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).