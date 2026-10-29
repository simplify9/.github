#!/usr/bin/env bash
# base_worktree must check out a base commit whose Git LFS objects are unavailable (CI has no LFS
# credentials). Re-runs itself in ubuntu:24.04 with git-lfs; skips when Docker is absent.
# Run: bash .github/actions/strapi-rehearsal/test_base_worktree_docker.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "${1:-}" != --inner ]; then
  if ! docker info >/dev/null 2>&1; then echo "::notice::Docker not available; skipping"; exit 0; fi
  exec docker run --rm -v "${here}:/r:ro" ubuntu:24.04 bash /r/test_base_worktree_docker.sh --inner
fi
{ apt-get update -qq && apt-get install -y -qq git git-lfs; } >/dev/null 2>&1 || { echo "FAIL apt"; exit 1; }
# shellcheck source=rehearse.sh
source /r/rehearse.sh
fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$2' got '$3'"; fails=$((fails + 1)); fi; }
git config --global user.email ci@example.invalid && git config --global user.name ci && git lfs install --skip-repo >/dev/null
repo=/tmp/repo && mkdir -p "${repo}" && cd "${repo}" && git init -q && git lfs track '*.mp4' >/dev/null
head -c 2048 /dev/urandom > seed.mp4 && git add .gitattributes seed.mp4 && git commit -qm base && base="$(git rev-parse HEAD)"
echo next > README && git add README && git commit -qm head
rm -rf .git/lfs/objects   # the object is gone, as in CI: smudging would have to download it
if git -c lfs.url=https://lfs.invalid/ worktree add --detach /tmp/plain "${base}" >/dev/null 2>&1; then plain=0; else plain=1; fi
eq plain_worktree_fails_without_object 1 "${plain}"
base_worktree "${repo}" /tmp/base "${base}" >/dev/null 2>&1
eq base_worktree_succeeds 0 $?
eq lfs_file_is_pointer 1 "$(grep -c '^version https://git-lfs.github.com/spec/v1' /tmp/base/seed.mp4 2>/dev/null)"
if [ "${fails}" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
