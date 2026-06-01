# iOS Pipeline Optimization — Progress Tracker

## Status Legend
- [ ] Not started
- [~] In progress
- [x] Complete

## Phase 1 — Split CocoaPods cache (spec repo always cached)
- [x] Spec repo cache step (`Cache CocoaPods spec repo`, always runs, id: `cache-pods-specs`)
- [x] Pods dir cache step (`Cache CocoaPods Pods directory`, id: `cache-pods-dir`, only when not clean-reinstalling)

## Phase 2 — Ruby/bundler setup
- [x] New inputs: `ruby-version` (string, default `""`) and `use-bundler` (boolean, default `false`)
- [x] `Setup Ruby (optional)` step using `ruby/setup-ruby@v1`, gated on `ruby-version != ''`

## Phase 3 — ccache (optional, opt-in)
- [x] New input: `enable-ccache` (boolean, default `false`)
- [x] Three steps added (all gated on `enable-ccache`):
  - `Install ccache (optional)` — installs via Homebrew if not present
  - `Cache ccache directory (optional)` — caches `~/Library/Caches/ccache`
  - `Configure ccache (optional)` — sets max-size=2G, compression=true, exports `CCACHE_DIR`

## Validation
- [x] `actionlint .github/workflows/generic-ios-testflight.yml` exits 0 with zero errors
- [x] No functional regression for existing callers (all new inputs default to inert values)

---

## Caller Prerequisites (do NOT overlook)

### ccache (`enable-ccache: true`)
Setting `enable-ccache: true` installs and caches ccache on the runner, but **does NOT automatically speed up compilation**. For ccache to intercept Xcode's compiler calls, the caller's **Podfile** must enable it — typically via the React Native post-install hook:

```ruby
react_native_post_install(installer, :ccache_enabled => true)
```

Without this Podfile change, ccache is present but never invoked. Document this requirement in the caller's README or Podfile comments.

### bundler (`use-bundler: true`)
Setting `use-bundler: true` (alongside a non-empty `ruby-version`)
causes `ruby/setup-ruby` to run `bundle install` and cache gems.
This requires a **Gemfile** (and ideally a `Gemfile.lock`) in the
caller repository. When both `use-bundler: true` and
`ruby-version` are set, the `Install CocoaPods (deployment mode)`
step automatically runs `bundle exec pod install --deployment`,
ensuring the CocoaPods version is taken from the Gemfile rather
than the system default.

---

## Phase 4 — Stop clean reinstalling pods, use deployment mode

### Changes made
- Added `Install CocoaPods (deployment mode)` step to
  `generic-ios-testflight.yml` — runs when both
  `clean-reinstall-pods=false` AND `use-simplify9-xcode-setup=false`
- Updated mealivery-customer-mobile caller:
  `clean-reinstall-pods: false`, `ruby-version: "3.2"`,
  `use-bundler: true`

### Expected impact
- Pod setup time: ~2.5 min → ~20-40 seconds on warm cache runs
- Run 1 (cold): populates spec repo cache and pods dir cache
- Run 2+ (warm): spec repo restored from cache,
  `bundle exec pod install --deployment` runs in seconds

### How the caching chain now works
1. `Cache CocoaPods spec repo` — restores `~/.cocoapods/repos`
   (always, even on clean reinstall paths)
2. `Cache CocoaPods Pods directory` — restores `ios/Pods`
   (since clean-reinstall-pods=false)
3. `Setup Ruby (optional)` — installs Ruby 3.2 + caches gems
   via bundler (since ruby-version="3.2" and use-bundler=true)
4. `Install CocoaPods (deployment mode)` — runs
   `bundle exec pod install --deployment`, reads Podfile.lock,
   installs exact pinned versions, fails fast if lock would change

### Note on `--deployment` flag
`pod install --deployment` is the CocoaPods equivalent of
`yarn install --frozen-lockfile`. It guarantees the installed
pods exactly match `Podfile.lock` and will fail the build if
any pod resolution would change the lock file. This is the
correct mode for CI.

