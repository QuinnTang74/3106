# 3106

3106 is an iOS container manager: browse app data, install patches, clean caches, and install PosterBoard wallpapers and dialer themes without a jailbreak.

**Repository:** <https://github.com/t479842598/3106.git>

[简体中文](README.md)

## Features

- **iOS 26/27 container access**: iOS 26.7–26.7.2 and iOS 27.0–27.3 beta use the `worse_query` sandbox escape; iOS 26.0–26.6.1 uses `bad_query`; iOS 17/18 keeps the kernel chain.
- **App data browser**: app containers, App Groups, extension data, and internal daemons; iOS 27 can list System Data and some System Groups.
- **Patch manager**: exports `.3106`, imports legacy `.3105`; multi-target, user inputs, optional password, and rollback on failure.
- **Cleaner, wallpapers, and dialer themes**: per-app cache cleaning, `.tendies` wallpapers, and `.3105pass` dialer themes.
- **Configurable tab bar**: toggle tab bar items in Settings, up to five slots, Home always shown; Developer Mode is enabled by default.
- **Three UI languages**: Simplified Chinese, English, and Vietnamese.

## Compatibility

| System | Verified range | Backend |
| --- | --- | --- |
| iOS 17 | 17.0–17.7.x | kernel chain |
| iOS 18 | 18.0–18.7.1 | kernel chain |
| iOS 26 | 26.0–26.6.1 | `bad_query` |
| iOS 26 | 26.7–26.7.2 | `worse_query` |
| iOS 27 | 27.0–27.2 | `worse_query` |
| iOS 27 | 27.3 beta 1 | `worse_query` (experimental) |

## Installation and signing

- **iOS 26.7+ / 27.x requires an App Group entitlement.** Sign with AltStore, SideStore, or Sideloadly using an Apple ID (a free account works); they create the App Group automatically.
- With a certificate (`.p12`) and provisioning profile, the profile must be an explicit App ID with the **App Groups** capability. Wildcard profiles cannot carry an App Group, and `worse_query` will report “No App Group”.
- **Bundle ID:** `com.qingtang.3106`.
- Whether LiveContainer keeps the App Group depends on its signing environment. Check **Settings → App Group**; if it is empty, `worse_query` cannot work.
- iOS 17/18 still needs the manual kernel chain; iOS 26/27 does not use a kernel exploit.

## Build

```bash
xcodebuild -project ThreeOneOSSix.xcodeproj -scheme 3106 \
  -configuration Release -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

Policy tests:

```bash
bash Tests/run_policy_tests.sh
```

Build output goes to `dist/`, named like `3106-3.1.1-unsigned.ipa`.

## License and commercial use

This repository is distributed under the **GNU GPL v3.0**; the full text is in [LICENSE](LICENSE).

The project contains GPL-3.0 code from 3105, `worse_query`, WQ Files, and others. GPL-3.0 does not permit an additional “non-commercial” restriction, so the combined work cannot be relicensed as a strictly non-commercial project.

The author does not want this project used commercially. For commercial use, please contact the repository author first. This sentence states the author's preference; it is not an additional restriction on GPL-3.0 and does not change the licenses of upstream or third-party code.

When modifying or redistributing, you must keep the copyright, origin, and license notices in [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md), and state what you changed. This is required by GPL-3.0 and by this project.

## Reference

This project references and is based on the **3105 project** (original author YangJiii) 2.0 source; the iOS 27 adaptation, `worse_query` port, and 3106 rename were built on top of it. Third-party copyright and origin notices are in [NOTICE.md](NOTICE.md) (required by GPL-3.0, not promotional content).