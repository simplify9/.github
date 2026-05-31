# Summary Output Cleanup — Progress Tracker

## Status Legend
- [ ] Not started
- [~] In progress
- [x] Complete

## Audit Results

### Composite actions with GITHUB_STEP_SUMMARY writes (all have a final "Write action summary" step)
- determine-semver/action.yml — L91
- docker-build-push/action.yml — L134
- dotnet-build/action.yml — L122
- dotnet-pack-push/action.yml — L164
- generate-wrangler-config/action.yml — L140
- helm-deploy/action.yml — L339
- helm-deploy-s9generic/action.yml — L407
- helm-generic/action.yml — L295
- helm-package-push/action.yml — L266
- ios-install-cert/action.yml — L62
- ios-install-profile/action.yml — L50
- setup-cloudflare-domain/action.yml — L152
- setup-cloudflare-project/action.yml — L138
- tag-github-origin/action.yml — L79
- upload-google-play-release/play_upload.py — L313-L314
- xcode-build/action.yml — L155
- xcode-export/action.yml — L49
- xcode-setup/action.yml — L98
- Actions with NO summary writes (xcode-related already covered above): none

### Workflow GITHUB_STEP_SUMMARY write locations
- api-cicd.yml: L211, L397, L447, L497, L547
- ci-docker.yaml: L203
- ci-helm.yaml: L345
- generic-android-google-play.yml: L241, L344, L432, L596, L702, L810
- generic-chart-helm.yml: L231, L317, L362, L506
- generic-gateway-chart-cicd.yml: L163, L409
- generic-gateway-helm-template.yml: L343, L429, L474, L904
- generic-ios-testflight.yml: L402, L893
- helm-deploy-values.yml: L277
- next-cloudflare-worker.yaml: L233
- next-static-cloudflare-worker.yaml: L203
- sw-cicd.yml: L202, L246, L386, L463
- vite-ci.yml: L277
- vite-cloudflare-worker.yml: L245
- android-google-play-dispatch-template.yml: none
- ios-testflight-dispatch-template.yml: none
- generic-gateway-helm-template.yml: L343, L429, L474, L904

---

## Phase 1 — Audit and remove ALL composite action summaries
- [x] Audit every action.yml under .github/actions/ for GITHUB_STEP_SUMMARY writes
- [x] determine-semver/action.yml
- [x] tag-github-origin/action.yml
- [x] docker-build-push/action.yml
- [x] dotnet-build/action.yml
- [x] dotnet-pack-push/action.yml
- [x] helm-deploy/action.yml
- [x] helm-deploy-s9generic/action.yml
- [x] helm-generic/action.yml
- [x] helm-package-push/action.yml
- [x] ios-install-cert/action.yml
- [x] ios-install-profile/action.yml
- [x] xcode-build/action.yml
- [x] xcode-export/action.yml
- [x] xcode-setup/action.yml
- [x] generate-wrangler-config/action.yml
- [x] setup-cloudflare-domain/action.yml
- [x] setup-cloudflare-project/action.yml
- [x] upload-google-play-release (play_upload.py — removed finally: block writing to GITHUB_STEP_SUMMARY)
- [x] No other actions with summary writes found

## Phase 2 — Remove intermediate workflow summary writes
- [x] generic-android-google-play.yml — removed 3 intermediate writes ("Record workflow provenance", "Compute version values", "Resolve package manager settings")
- [x] generic-ios-testflight.yml — removed 1 intermediate write ("Resolve package manager settings")
- [x] ci-docker.yaml — no intermediate writes (only final)
- [x] ci-helm.yaml — no intermediate writes (only final)
- [x] helm-deploy-values.yml — no intermediate writes (only final)
- [x] generic-chart-helm.yml — no intermediate writes (all final)
- [x] api-cicd.yml — no intermediate writes (all 5 are final)
- [x] sw-cicd.yml — no intermediate writes (all 4 are final)
- [x] generic-gateway-chart-cicd.yml — no intermediate writes (both final)
- [x] generic-gateway-helm-template.yml — no intermediate writes (all 4 are final)
- [x] next-cloudflare-worker.yaml — no intermediate writes (only final)
- [x] next-static-cloudflare-worker.yaml — no intermediate writes (only final)
- [x] vite-ci.yml — no intermediate writes (only final)
- [x] vite-cloudflare-worker.yml — no intermediate writes (only final)
- [x] android-google-play-dispatch-template.yml — no summary writes
- [x] ios-testflight-dispatch-template.yml — no summary writes

## Phase 3 — Polish final workflow summary steps
- [x] generic-android-google-play.yml — build job: full replacement per spec (added heading + App/Version/Track/Branch/Run fields); release: dynamic status; release_with_environment: dynamic status
- [x] generic-ios-testflight.yml — build job: full replacement (fixed heading + dynamic status; corrected Runner field)
- [x] ci-docker.yaml — added dynamic status heading
- [x] ci-helm.yaml — added dynamic status heading
- [x] helm-deploy-values.yml — added dynamic status heading
- [x] api-cicd.yml — added dynamic status to all 5 job summaries
- [x] generic-chart-helm.yml — added dynamic status to all 4 job summaries
- [x] generic-gateway-chart-cicd.yml — added dynamic status to both summaries; added missing `if: always()` to "Workflow summary" step
- [x] generic-gateway-helm-template.yml — added dynamic status to all 4 job summaries
- [x] sw-cicd.yml — added dynamic status to all 4 job summaries
- [x] next-cloudflare-worker.yaml — added dynamic status heading
- [x] next-static-cloudflare-worker.yaml — added dynamic status heading
- [x] vite-ci.yml — added dynamic status heading
- [x] vite-cloudflare-worker.yml — added dynamic status heading

## Phase 4 — Validation
- [x] actionlint passing on all 14 modified workflow files — exit 0, zero errors
- [x] No functional logic changes in any file
- [x] SUMMARY_CLEANUP.md fully complete
