# Changelog

All notable user-facing changes are documented in this file.

## [3.1.6] - 2026-11-10

### Added

- Folder favorites: long-press a folder in the file browser and choose “Add to Favorites”. The JSON key and shape (`fileBrowserFavorites`, `id`/`path`/`name`) match 3105 2.0, so existing favorites survive the upgrade.
- Favorite paths are normalized (`/var` and `/private/var` are the same entry, trailing slashes ignored, duplicates removed).
- The file tab switcher (top-right) now has an inline Favorites section at the top, matching 3105 2.0’s actual layout: it lists each favorited folder’s name and full path directly, with swipe-to-remove, and tapping a row opens it in a new tab. There is no separate favorites screen and no Favorites entry in the Files home.
- Long-press favorite actions work in both normal and read-only file browsers (favoriting is local state, not a container write).

### Changed

- Marketing version **3.1.6**; `CFBundleVersion` **10**.

## [3.1.5] - 2026-11-10

### Fixed

- App Data browser no longer hides containers whose bundle identity cannot be resolved. The former `shouldShow` policy dropped every UUID-named container; they now appear in a separate “Unidentified containers” section, are browsable read-only, and are excluded from selection and write actions.
- Removed the hard-coded `com.apple.mobile.MobileHouseArrest` guard in `MCMActivateContainerPath`. After the 3106 rename to `com.qingtang.3106`, that guard made every MCM enumeration and lookup fail, which was the root cause of the missing app data.
- Added a LaunchServices `bdsl` CSStore parser (Swift port of WQ Files) that maps container paths to bundle ids directly, without MCM, the container identifier xattr, or the root-owned metadata plist. It reads lsd’s store from the Internal Daemon container and covers the 26 / 27.0 / 27.2 record layouts.
- Discovery now merges the LaunchServices store’s container list with the filesystem scan, and API/ MCM lookups fall back to the store path instead of dropping apps with an empty or bundle-only container.
- `installedAppInfo` now merges LaunchServices workspace and MobileInstallation results, and both enumeration selectors (`allApplications` / `allInstalledApplications`) and MobileInstallation option sets are unioned instead of “first non-empty wins”.
- The progress callback during the MHA candidate scan no longer replaces the list with identified-only entries, so the browser does not visibly shrink while scanning.
- Cleaner scans unidentified containers too and shows their `Library/Caches` + `tmp` usage, but marks them with a lock and disables selection/cleaning.

### Changed

- App Data browser rows for unidentified containers use a read-only file browser: import, new file/folder, paste, rename, delete, replacement, archive extraction, and patch creation are hidden.
- Marketing version **3.1.5**; `CFBundleVersion` **8**.

## [3.1.4-r2] - 2026-11-10

### Changed

- Project repository moved to `QuinnTang74/3106`; the in-app GitHub link, update checker API, README, and release links now point to the new address.
- App marketing version remains **3.1.4**; `CFBundleVersion` is now **7**.

## [3.1.4] - 2026-11-10

### Fixed

- Cleaner deletion uses the container path captured during the scan instead of re-resolving by bundle id; MCM being unavailable no longer turns selected apps into “bundle unavailable”.
- Cleaner removes `Library/Caches` and `tmp` contents through `FileManager` and only follows a symlinked Caches when its resolved target stays inside the app container.
- Added `cleaner: cleaning …`, `remove failed …`, and symlink-refusal diagnostics.

## [3.1.3] - 2026-11-10

### Fixed

- Wallpaper scanner accepts nested/non-standard PosterBoard stores by recursively locating `descriptors` directories.
- When no descriptor directory exists, the device scanner creates the required extension/descriptors path under the highest numeric generation, an existing `Extensions` directory, or the default `61/Extensions` layout.
- Synthetic layout creation is disabled for `.tendies` package scans, so package contents are never modified.
- Added a bounded PosterBoard store tree and recursive-descriptor diagnostic to the app log.

## [3.1.2] - 2026-11-10

### Fixed

- Cleaner measures `Library/Caches` and `tmp` with `FileManager` enumeration instead of `openat(O_NOFOLLOW)`, which rejected symlinked Caches directories and reported every app as empty.
- Cleaner prefers the container path already discovered by filesystem enumeration instead of re-resolving it through MCM.
- Cleaner shows the Settings gear at all times, including the empty/scan state.
- Wallpaper resolves PosterBoard by scanning app-data containers for `Library/Application Support/PRBPosterExtensionDataStore` when MCM and the bundle-id index both fail.
- Wallpaper view and service share the same fallback resolver; diagnostics now include the chosen container path.

## [3.1.1] - 2026-11-10

### Fixed

- Cleaner now enumerates app-data containers from the filesystem when MCM/LaunchServices return nothing (LiveContainer and similar signing environments).
- Cleaner resolves container paths through the iOS 27.2+ identifier index and no longer marks an app as scanned before its container was actually measured.
- Cleaner explicitly grants `Library/Caches` and `tmp` before measuring, matching WQ Files' grant-before-access pattern.
- Wallpaper layout scan, access probe, install, and reset now grant the PosterBoard container and descriptor directories before reading or creating probe files.
- Added a reverse container-index fallback plus `wallpaper:` / `cleaner:` diagnostics in the app log.

## [3.1.0] - 2026-11-10

### Added

- Settings now has tab bar toggles: up to five slots, Home always shown. Default slots are Home, New, Installed, Files, and Cleaner.
- Developer Mode is enabled by default.

### Changed

- Removed the social media and credits sections from Settings; the only link kept is the project repository.
- README is now Chinese-first with an English entry. Promotional content and the Vietnamese README were removed.
- `THIRD_PARTY_NOTICES.md` became `NOTICE.md`, containing only the attribution required by GPL-3.0.
- The license section now explains that the GPL-3.0 code cannot carry an additional non-commercial restriction, while retaining the author's commercial-use request and the mandatory attribution requirement.

### Compatibility

- iOS 27.3 beta 1 is exposed as an experimental `worse_query` target (device build 24C5037i).

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
