# Changelog

All notable user-facing changes are documented in this file.

## [3.0.0] - 2026-11-10

### Added

- `worse_query` sandbox backend for iOS 26.7–26.7.2 and iOS 27.0–27.2, ported from Taj C (forcequitOS) with the Caches-swap recovery, grant cache, and open verification adapted from WQ Files.
- Container identifier fallback through `container_query_iterate_results_sync` for iOS 27.2, where the identifier xattr and metadata plist are unreadable.
- App Group entitlement and a Settings row showing the active backend and App Group status.
- `.3106` patch extension for new exports; legacy `.3105` packages remain importable and decrypt with the unchanged `3105PATCH` format.

### Changed

- Project, target, scheme, product name, bundle identifier, URL scheme, localized strings, and documentation renamed from 3105 to 3106.
- Bundle identifier is now `com.qingtang.3106`; the MHA-C2 spoof was retired because it cannot carry an App Group for `worse_query`.
- iOS 26.0–26.6.1 keeps `bad_query`; iOS 26.7+ and 27.x automatically select `worse_query`.
- Signing guidance now targets AltStore/SideStore/Sideloadly with a free Apple ID, or an explicit App ID with App Groups.

### Fixed

- System Data/System Groups visibility follows the active backend (iOS 26 hides them; iOS 27 shows them).
- File browser, cleaner, patch transaction, and wallpaper installer now hold container grants for the whole operation.

### Compatibility

- Verified iOS 17.0–17.7.x and 18.0–18.7.1 (kernel exploit).
- Verified iOS 26.0–26.6.1 (`bad_query`) and 26.7–26.7.2 (`worse_query`).
- Verified iOS 27.0–27.2 (`worse_query`); 27.3 beta is experimental.

## [1.0.1] - 2026-08-15

### Added

- Bundle-tree Patch workspace v2 under `On My iPhone/3105/Patches`, synchronized automatically when applying or exporting.
- Multiple independent Files tabs with preserved navigation state.
- ZIP extraction with path, symbolic-link, CRC, and available-space validation.
- Responsive iPad split-view and landscape navigation.
- Home toggles for showing or hiding Cleaner and Wallpaper features.

### Changed

- Patch creation from an app-container file or folder now captures the stable bundle identifier and editable destination tree automatically.
- Patch package imports no longer use the previous fixed payload-size or file-count ceiling; practical device storage and memory still apply.
- Files and Patch screens now use consistent grouped cards, compact icons, balanced nested rows, and stable search presentation.
- Legacy v1 `.3105` packages remain importable and usable.

### Fixed

- Patch Restore now restores files that existed before Apply, removes files introduced by the patch, and removes patch-created folders after they become empty.
- File navigation remains at the current folder when switching app sections and restores the correct folder independently for each Files tab.
- Empty Patch and Cleaner actions now share the same visual treatment.
- Corrected PosterBoard wallpaper activation guidance and the iOS 27 Collections prerequisite.
- Refined navigation icon rendering and nested file-row spacing.

### Compatibility

- Verified iOS 26.0–26.6.1.
- Verified iOS 27 Developer Beta 1–4, including Public Beta 1–2 mappings listed in the app.
- Added iPhone and iPad interface support; device-level features still require enterprise signing.

## [1.0 beta 3] - 2026-08-14

### Added

- Bundle-based App Data Browser with MHA-C2 container discovery.
- Native file operations: search, multi-file import, rename, delete, create file/folder, and conflict handling.
- Portable `.3105` patch projects with optional password protection and file/folder rules.
- Limited per-app cleaner for `Library/Caches` and `tmp`.
- Wallpaper Lab for validated `.tendies` packages with installation receipts and targeted reset.
- English, Vietnamese, and Simplified Chinese localization.

### Changed

- Simplified the app into a five-tab, native SwiftUI layout inspired by focused iOS container tools.
- Moved the enterprise-signing notice below device information on Home.
- Refined the orange accent, empty states, actions, and navigation presentation.

### Fixed

- Stabilized persistent search presentation in app and file browsers.
- Fixed native document selection for replacement files and `.3105` package imports.
- Resolved bundle-name mapping for enumerated app containers where metadata is available.
- Limited wallpaper reset to active content installed by 3105.
- Corrected Cleaner layout when no removable app data is found.

### Compatibility

- Verified iOS 26.0–26.6.1.
- Verified iOS 27 beta 1–4 builds listed in the app.
- Unlisted iOS 27 builds remain disabled until explicitly verified.
