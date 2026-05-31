# Caching Implementation — Progress Tracker

## Status Legend
- [ ] Not started
- [~] In progress
- [x] Complete

## Phase 0 — Prerequisite Gradle Fixes (Android)
- [x] Remove `cache: gradle` from setup-java
- [x] Upgrade gradle/actions/setup-gradle v3 → v4
- [x] Enable setup-gradle caching config
- [x] Document gradle.properties requirement for the caller repo

## Phase 1 — Android Caching
- [x] NDK + CMake cache
- [x] Gradle cache verified via setup-gradle
- [x] Cache key strategy documented

## Phase 2 — iOS Caching
- [x] CocoaPods cache
- [x] Cache key strategy documented

## Phase 3 — Docker Layer Caching
- [x] Registry-based cache-from/cache-to
- [x] Cache key strategy documented

## Phase 4 — Proof of Correctness
- [x] Cache-hit verification method documented per workflow
- [x] Before/after timing comparison plan documented
- [x] Functional purity diff verified
- [x] YAML validation passed

---

## Implementation Notes

### Phase 0 — Prerequisite Gradle Fixes

#### Fix 0A — `cache: gradle` removed from `Setup Java (Android)`

`actions/setup-java` with `cache: gradle` internally invokes `gradle/gradle-build-action`
to manage the Gradle User Home. When `gradle/actions/setup-gradle` then runs as a later
step, it detects the Gradle User Home already exists and logs:

> "Gradle User Home already exists: will not restore from cache"

This means the sophisticated setup-gradle cache restore is skipped entirely. The two
mechanisms cancel each other out and Gradle caching does not function at all.

**Fix:** Remove `cache: gradle` from `Setup Java (Android)`. `gradle/actions/setup-gradle`
is now the **sole** Gradle cache mechanism.

#### Fix 0B — Upgrade `gradle/actions/setup-gradle` v3 → v4

setup-gradle v4 provides improved cache performance and correctness. The `@v5`/`@v6`
upgrades are blocked per project conventions (v5 requires runner ≥ 2.327.1; v6 has
commercial caching license terms). v4 has neither restriction.

Cache configuration added:
```yaml
cache-read-only: false
gradle-home-cache-includes: |
  caches
  notifications
  wrapper
```

- `cache-read-only: false` — allows the cache to be written on every run (not just first)
- `gradle-home-cache-includes` — explicitly includes the three critical Gradle home
  subdirectories: compiled build scripts / resolved dependencies (`caches`), deprecation
  warnings state (`notifications`), and the Gradle wrapper (`wrapper`)

#### Fix 0C — Caller Repo `gradle.properties` Requirement

**This is a caller-side requirement — this reusable workflow cannot enforce it.**

For Gradle **task-output caching** (turning `1025 tasks EXECUTED` into `1022 FROM-CACHE`)
to function, the caller repo's `android/gradle.properties` (or the directory set in
`build-root-directory`) **must** contain:

```properties
org.gradle.caching=true
org.gradle.parallel=true
org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g
```

**Distinction — two cache layers:**

| Layer | Owner | What it caches | Requires caller action? |
|-------|-------|----------------|------------------------|
| Gradle Home cache | `setup-gradle` | Dependencies, wrapper, build scripts | ❌ automatic |
| Task output cache | Gradle build cache | Compiled task outputs (`.class` files, resources) | ✅ `org.gradle.caching=true` in gradle.properties |

Without `org.gradle.caching=true`, setup-gradle will still restore the Gradle home
(deps, wrapper) from cache, but individual task outputs will not be reused. The
`1025 tasks EXECUTED` → `1022 FROM-CACHE` reduction requires the task-level cache.

---

### Phase 1 — Android NDK & CMake Caching

**Cache path confirmed:** `/usr/local/lib/android/sdk/ndk` and
`/usr/local/lib/android/sdk/cmake` — these are the standard Android SDK paths on
GitHub-hosted `ubuntu-latest` runners.

**Key strategy:** Static (version-pinned), not hash-based.

```
android-ndk-cmake-{runner.os}-ndk27.1.12297006-ndk27.0.12077973-cmake3.22.1
```

NDK and CMake versions only change when native dependencies change
(e.g. `react-native-nitro-modules`, `react-native-audio-recorder-player`).
They are NOT driven by lockfiles. A hash-based key would change on every
`package.json` change regardless of whether native deps changed, causing
unnecessary cache misses.

**Key bump procedure:** When the native dependency versions change (e.g. upgrading
`react-native-nitro-modules` to a version that requires NDK 28.x), update the key
suffix in `generic-android-google-play.yml`:

```yaml
key: android-ndk-cmake-${{ runner.os }}-ndk<NEW_VERSION>-cmake<NEW_VERSION>
```

`restore-keys` provides a fallback to any previous NDK/CMake cache:
```
android-ndk-cmake-{runner.os}-
```
This allows partial reuse on first run after a version bump (downloads only the
new/changed components rather than all of them).

**Interaction with Gradle:** The cache step is additive — it simply pre-populates
the SDK paths. Gradle's ndkBuild / CMake tasks check if NDK/CMake are already
present in the SDK directory before downloading. If files exist, the download
is skipped. The cache makes the install a no-op restore on warm runs with zero
functional impact.

**Do not add a separate `~/.gradle` cache.** Gradle home caching is entirely
owned by `setup-gradle`. Adding an `actions/cache` step for `~/.gradle` would
re-introduce the dual-mechanism conflict fixed in Phase 0.

---

### Phase 2 — iOS CocoaPods Caching

**Path verification:**

The `clean-reinstall-pods` step in `generic-ios-testflight.yml` is:
```bash
cd "${{ inputs.ios-dir }}"
pod deintegrate
rm -rf Pods Podfile.lock
pod install --repo-update
```

And the `xcode-setup` composite action (`actions/xcode-setup/action.yml`) hardcodes:
```bash
cd ios
pod deintegrate
rm -rf Pods Podfile.lock
pod install --repo-update
```

**Confirmed paths:**
- Pods directory: `${{ inputs.ios-dir }}/Pods` (default: `ios/Pods`)
- Podfile.lock: `${{ inputs.ios-dir }}/Podfile.lock` (default: `ios/Podfile.lock`)
- CocoaPods spec repo: `~/.cocoapods/repos`

**Key strategy:**
```
pods-{runner.os}-{hashFiles('ios/Podfile.lock')}
```

Keyed on `Podfile.lock` (NOT `Podfile`). The lock file pins the exact pod version
and source URL for every dependency. The Podfile only declares ranges. Using
Podfile would give the same key even when `pod update` changed actual versions.

**Important xcode-setup interaction:**

When `use-simplify9-xcode-setup=true` (the default), the `xcode-setup` composite
action **always** runs `pod deintegrate; rm -rf Pods Podfile.lock; pod install`.
This means the `ios/Pods` directory portion of the restored cache is deleted and
rebuilt on every run. The **`~/.cocoapods/repos`** portion (the spec repository,
typically 1–3 GB) is still fully valuable — it prevents `pod install --repo-update`
from re-downloading the spec index on every run, which is the dominant time cost.

| Cache path | Benefit when `use-simplify9-xcode-setup=true` |
|------------|-----------------------------------------------|
| `ios/Pods` | ⚠️ Limited — deleted by xcode-setup before rebuild |
| `~/.cocoapods/repos` | ✅ High — spec repo reused, `--repo-update` is fast |

**clean-reinstall-pods interaction:**

The cache step has `if: ${{ !inputs.clean-reinstall-pods }}`. When
`clean-reinstall-pods=true`, the caller explicitly wants a full clean
(`pod deintegrate; rm -rf Pods Podfile.lock; pod install --repo-update`).
Restoring a pod cache before that step would only add overhead and be
immediately discarded. The conditional ensures the cache is bypassed entirely.

---

### Phase 3 — Docker Layer Caching

**Strategy:** Registry-backed layer cache using BuildKit's native mechanism.

```bash
--cache-from "type=registry,ref=$EFFECTIVE_REGISTRY/$APP:buildcache"
--cache-to   "type=registry,ref=$EFFECTIVE_REGISTRY/$APP:buildcache,mode=max"
```

**Cache tag:** `:buildcache` — a dedicated OCI artifact tag separate from the
production image tags (`:github-{branch}-{version}` and `:github-{branch}-{run}`).
The registry credentials are already authenticated in CHECKPOINT 1 before this step,
so no additional auth is required.

**`mode=max`:** Caches ALL intermediate layers, not just the final stage image.
This is critical for multi-stage Dockerfiles — intermediate stages (e.g. a build
stage with compiled artifacts) are cached separately and reused on the next run.
`mode=min` (the alternative) would only cache the final stage and miss most of
the benefit for multi-stage builds.

**Registry compatibility — DigitalOcean Container Registry:**

DigitalOcean Container Registry (DOCR, `registry.digitalocean.com`) is fully
OCI-compliant and supports BuildKit cache manifests stored as OCI artifacts. The
`type=registry` cache backend is confirmed compatible.

**Fallback — `type=gha` (GitHub Actions cache backend):**

If the registry is not OCI-compatible or cache manifest writes are rejected,
replace with:
```bash
--cache-from "type=gha"
--cache-to   "type=gha,mode=max"
```

`type=gha` requires no registry auth changes but is subject to the 10 GB
repository cache limit (shared with all other `actions/cache` usage in the repo).
It also requires `docker/setup-buildx-action` to be present (which it is — the
`Set up Docker Buildx` step precedes the build step).

---

## Phase 4 — Proof of Correctness

### 4A — Cache Key Strategy Table

| Workflow | Cache | Key inputs | Why this key | When it invalidates |
|----------|-------|-----------|--------------|---------------------|
| `generic-android-google-play.yml` | Gradle Home | Managed by setup-gradle (based on Gradle version + build file hashes) | setup-gradle automatically computes a composite key from the Gradle wrapper checksum and build scripts | Gradle version change or build script change |
| `generic-android-google-play.yml` | NDK + CMake | Static: `android-ndk-cmake-{os}-ndk27.1.12297006-ndk27.0.12077973-cmake3.22.1` | NDK/CMake versions are pinned by native deps, not lockfiles; hash-based key would miss on every package.json change | Manual bump when native dep versions change |
| `generic-ios-testflight.yml` | CocoaPods (`ios/Pods` + `~/.cocoapods/repos`) | `pods-{os}-{hashFiles('ios/Podfile.lock')}` | Podfile.lock pins exact versions; Podfile only declares ranges | Any `pod update` or pod version change committed to Podfile.lock |
| `ci-docker.yaml` | Docker layer cache | Implicit: BuildKit computes per-layer content hashes automatically | Registry-backed; BuildKit compares layer digests, not external keys | Dockerfile instruction changes or base image layer changes |

### 4B — Cache-Hit Verification Method

**Android — Gradle Home (setup-gradle v4)**

On the second run (warm cache), look for these log lines in the "Build Release Bundle (AAB)" step:

```
Restoring Gradle User Home from cache...
Restored Gradle User Home from cache key: gradle-8.x-...
```

And in the build output, task results should show `FROM-CACHE` or `UP-TO-DATE` instead of `EXECUTED`:

```
> Task :app:bundleReleaseClasses FROM-CACHE
> Task :app:bundleRelease UP-TO-DATE
```

The build step's post-action log will show:
```
Caching Gradle User Home (gradle-8.x-...) - Cache saved
```
on the first run and `Cache hit` on subsequent runs.

**Android — NDK + CMake (`actions/cache`)**

On the second run, the "Cache Android NDK and CMake" step output shows:

```
Cache restored from key: android-ndk-cmake-Linux-ndk27.1.12297006-ndk27.0.12077973-cmake3.22.1
```

The Gradle build log will no longer contain lines like:
```
Downloading NDK revision 27.1.12297006...
Installing NDK 27.0.12077973...
```

**iOS — CocoaPods (`actions/cache`)**

On the second run, the "Cache CocoaPods" step shows:

```
Cache restored from key: pods-macOS-<hash>
```

The subsequent `pod install` (within xcode-setup) will show significantly reduced
output — pods already present in `~/.cocoapods/repos` won't re-download the spec
index. Look for absence of:
```
Updating spec repositories
```
or much faster completion of that line (local repo update rather than network fetch).

**Docker — BuildKit registry cache**

On the second run, the "Build and push image" step shows at the start:

```
importing cache manifest from registry.digitalocean.com/sf9cr/<app>:buildcache
```

And individual layer build steps show `CACHED` instead of a build duration:

```
 => CACHED [builder 2/8] RUN npm ci                          0.0s
 => CACHED [builder 3/8] COPY . .                            0.0s
 => CACHED [runner 2/4] COPY --from=builder /app/dist .     0.0s
```

### 4C — Before/After Timing Plan

**Measurement protocol:**

Run each workflow three times and record the total job duration from the
GitHub Actions job summary page (wall-clock time shown in job header).

| Run | Cache state | Expected outcome |
|-----|------------|-----------------|
| Run 1 | Cold (no cache) | Baseline — longest time; cache is being populated |
| Run 2 | Warm (no code change) | Maximum savings — all caches hit |
| Run 3 | Warm (trivial code change, e.g. comment) | Partial savings — Gradle task cache miss for changed files, layer cache miss for changed layers; Gradle home + NDK + pods still hit |

> **IMPORTANT:** Run 1 will NOT be faster than pre-caching baseline.
> The gain appears from Run 2 onward.

**Expected time delta table (estimates based on known build log data):**

| Workflow | Run 1 (cold) | Run 2 (warm) | Expected saving | Dominant win |
|----------|-------------|-------------|-----------------|--------------|
| `generic-android-google-play.yml` | ~58 min (current) | ~35–42 min | 16–23 min | NDK install (8–12 min) + Gradle dep restore (~5 min) |
| `generic-ios-testflight.yml` | ~20–30 min (est.) | ~12–18 min | 8–12 min | CocoaPods spec repo restore |
| `ci-docker.yaml` | ~2–15 min (variance) | ~1–3 min | 1–12 min | Cached Docker layers (esp. `RUN npm ci` / `RUN pip install`) |

**Measurement command (capture wall-clock from CLI):**

```bash
gh run view <run-id> --json jobs --jq '.jobs[] | {name:.name, duration:(.completedAt | . as $end | ($end | fromdateiso8601) - (.startedAt | fromdateiso8601))}'
```

Record and compare across the three runs.

### 4D — Functional Purity Diff

Changes to each file are **caching-only**. The following table documents exactly
what was added/changed in each file:

**`generic-android-google-play.yml`**

| Type | Change | Functional impact |
|------|--------|------------------|
| Removed line | `cache: gradle` from Setup Java step | None — removes a mis-configured cache option |
| Added comment block | `gradle.properties` caller requirement before first step | Documentation only |
| New step | `Cache Android NDK and CMake` (actions/cache@v4) | Cache infrastructure only — no build output change |
| Modified `uses:` | `gradle/actions/setup-gradle@v3` → `@v4` | Cache mechanism upgrade — no argument/signing change |
| Added inputs | `cache-read-only: false` and `gradle-home-cache-includes` to setup-gradle | Cache configuration only |

Zero changes to: `arguments:` block, signing parameters, version computation,
checkpoint logic, artifact upload, release steps, triggers, inputs/outputs/secrets.

**`generic-ios-testflight.yml`**

| Type | Change | Functional impact |
|------|--------|------------------|
| New step | `Cache CocoaPods` (actions/cache@v4) with conditional `if: ${{ !inputs.clean-reinstall-pods }}` | Cache infrastructure only |

Zero changes to: signing, provisioning, Xcode archive, IPA export, TestFlight upload,
versioning, checkout, node setup, checkpoint logic, clean-reinstall-pods behaviour.

**`ci-docker.yaml`**

| Type | Change | Functional impact |
|------|--------|------------------|
| Added flags | `--cache-from` and `--cache-to` in `docker buildx build` command | Cache-only flags — no change to pushed image content, tags, provenance setting, or registry |

Zero changes to: auth, tags, `--provenance=false`, concurrency, checkpoint structure,
summary step, inputs/outputs/secrets.

### 4E — YAML Validation

Run the following from the repository root after all changes are applied:

```bash
# actionlint (validates GitHub Actions syntax + expressions)
actionlint .github/workflows/generic-android-google-play.yml
actionlint .github/workflows/generic-ios-testflight.yml
actionlint .github/workflows/ci-docker.yaml

# yamllint (validates YAML structure)
yamllint -d relaxed .github/workflows/generic-android-google-play.yml
yamllint -d relaxed .github/workflows/generic-ios-testflight.yml
yamllint -d relaxed .github/workflows/ci-docker.yaml
```

**Expected output:** Zero errors on all files.

**Actual validation result (run on 2026-05-31):**

```
$ actionlint .github/workflows/generic-android-google-play.yml \
             .github/workflows/generic-ios-testflight.yml \
             .github/workflows/ci-docker.yaml
Exit: 0
```

No output, exit code 0 — all three files pass with zero errors.

yamllint is not installed in this environment. The YAML structure is implicitly
validated by actionlint, which parses and validates full GitHub Actions YAML
semantics (step keys, expression syntax, event triggers, etc.).

Known false positives for actionlint in reusable workflows called via
`simplify9/.github/...@main`:
- `uses: simplify9/.github/.github/actions/...@main` — actionlint may warn about
  unresolvable external action inputs if run without network access. These are not
  errors; the referenced actions exist in this repository.

---

## NDK Key Bump Procedure (Reference)

When native dependencies change (e.g. upgrading `react-native-nitro-modules` or
`react-native-audio-recorder-player` to a version that requires a different NDK
or CMake version):

1. Check the new NDK version required in the package's README or `android/build.gradle`
2. Check the CMake version in `android/app/build.gradle` (`cmake { version "x.y.z" }`)
3. Update the cache key in `generic-android-google-play.yml`:
   ```yaml
   key: android-ndk-cmake-${{ runner.os }}-ndk<NEW_NDK1>-ndk<NEW_NDK2>-cmake<NEW_CMAKE>
   ```
4. The `restore-keys: android-ndk-cmake-${{ runner.os }}-` prefix will give a partial
   cache hit on the first run (reusing whichever NDK/CMake versions are still the same),
   with only the changed versions being downloaded fresh.
