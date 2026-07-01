# Flutter iOS & Android Reusable CI/CD — Design

**Date:** 2026-06-30
**Status:** Implemented
**Author:** DevOps (with Claude Code)

## Goal

Add two **new** reusable workflows to the Simplify9 `.github` library that build,
sign, and ship **Flutter** apps — a **drop-in replacement** for the hand-written
custom CI/CD currently living in `laflef-mobile`, and reusable by any other
Flutter app in the org (e.g. `yousefafandi-franovo-booking/mobile`).

These are additive. The existing `ios-build.yml` / `android-build.yml` are
**React Native** workflows (Node/yarn/jetifier/NDK/CocoaPods-for-RN) and keep
their own files — Flutter's toolchain differs enough to warrant separate ones.

## Reference (source of truth for build parity)

| Reference file | What it does |
|---|---|
| `laflef-mobile/.github/workflows/testflight.yml` | iOS: `macos-26` + Xcode 26.3, `flutter build ipa`, manual signing, TestFlight via `apple-actions/upload-testflight-build@v5` |
| `laflef-mobile/.github/workflows/laflef-android-cicd.yml` | Android: `flutter build appbundle`, `key.properties` signing, Play via `r0adkll/upload-google-play@v1` |

`yousefafandi-franovo-booking/mobile` is a source-only Flutter module (no
`android/`, `ios/`, or workflows) — not usable as a CI reference, but the
`project-directory` input makes these workflows adoptable there once it has
platform folders.

## Deliverables

```
.github/workflows/flutter-ios-build.yml          # reusable (on: workflow_call)
.github/workflows/flutter-android-build.yml      # reusable (on: workflow_call)
workflow-templates/flutter-ios-app.yml + .properties.json
workflow-templates/flutter-android-app.yml + .properties.json
README.md / AGENTS.md / CLAUDE.md                # docs reconciled
```

## Architecture

Each reusable workflow keeps the repo's established **two-job pattern**:

```
build (artifact producer)
  └── release_with_environment (artifact consumer)
        gated by: release-environment != '' && !disable-release
        bound to: environment: <release-environment>
```

Per-branch dev/prod selection happens in the **caller template**, never inside
the reusable workflow — same as the RN templates.

### Reuse decisions

- **iOS signing** → `ios-install-cert@main` + `ios-install-profile@main`. They
  export `KEYCHAIN_PATH`, `IOS_PROFILE_NAME`, `IOS_PROFILE_UUID` but not
  `team_id`/`bundle_id`, so the iOS workflow keeps one inline "extract profile
  metadata" step, exactly like the RN `ios-build.yml`.
- **Summaries** → `write-job-summary@main` (Pillar 4).
- **4-pillar logging** → `::notice::` announce, `::group::` checkpoints,
  namespaced status env vars, canonical emoji.

### Monorepo support — `project-directory`

Both workflows accept an optional `project-directory` input (default `.`). It is
applied via step-level `working-directory` on the file-touching `run` steps (so
the script bodies stay identical to the laflef reference) plus path/cache-key
prefixes on the `uses:` steps. Default `.` is byte-identical to repo-root builds;
set it to e.g. `mobile` for a nested Flutter app in a monorepo.

## Versioning — SemVer patch counter

`major.minor` are fixed by the developer (`version-prefix` for Android, the
`pubspec.yaml` marketing version for iOS). Only the patch increments — by exactly
1 per run — as `patch = base patch + run_number`, with **no carry/rollover and no
upper bound** (… `1.1.69 → 1.1.70` …). The build identifiers stay decoupled and
strictly monotonic for store acceptance: Android `versionCode = run_number +
version-code-offset`; iOS `CFBundleVersion = pubspec base build + run_number`.

`github.run_number` is per-workflow-file, so in a monorepo an unrelated pipeline
(backend/web) never advances the mobile patch — only a run of the mobile
workflow does.

## `flutter-android-build.yml`

**Inputs:** `ubuntu-runner`, `flutter-version` (`3.x`), `flutter-channel`,
`java-version`/`java-distribution`, `app-id` (**required**), `app-slug`,
`project-directory` (`.`), `version-prefix`, `version-name-override`,
`version-name-offset`, `version-code-offset`, `run-analyze` (`true`),
`analyze-fatal-level` (`none`), `keystore-output-path`, `aab-name-pattern`,
`artifact-name`, `play-track`, `release-status` (`draft`),
`changes-not-sent-for-review`, `release-environment`, `disable-release`.

**Secrets (names unchanged):** `android-keystore-base64`,
`android-keystore-password`, `android-key-alias`, `android-key-password`
(required); `google-play-service-account-json` (optional).

**Outputs:** `version-name`, `version-code`, `aab-file`.

## `flutter-ios-build.yml`

**Inputs:** `macos-runner`, `xcode-version`, `flutter-version` (`3.x`),
`flutter-channel`, `project-directory` (`.`), `ios-dir`, `pbxproj-path`,
`app-slug`, `export-method` (`app-store-connect`), `run-analyze` (`false`),
`ipa-name-pattern`, `artifact-name`, `wait-for-processing` (`false`),
`release-environment`, `disable-release`.

**Secrets (names unchanged):** `ios-p12-base64`, `ios-p12-password`,
`ios-mobileprovision-base64` (required); `ios-team-id`, `appstore-api-key-id`,
`appstore-issuer-id`, `appstore-api-private-key-base64` (optional, required for
upload).

**Outputs:** `version`, `build-number`, `ipa-file`.

## Build-parity guarantees (drop-in replacement)

Behavior-bearing logic (signing, build commands, cache keys, upload actions,
secret names) is copied verbatim from the laflef reference. Intentional deltas:
hardcoded identity → inputs; inline summaries → `write-job-summary@main`;
floating Flutter → pinnable `flutter-version`; iOS `app-store` →
`app-store-connect`; carry-rollover patch → SemVer patch counter;
`project-directory` for monorepos.

## Out of scope

- Modifying RN `ios-build.yml` / `android-build.yml` structure (only the shared
  patch-counter versioning change was applied to them).
- Firebase App Distribution, Fastlane, or other stores.
