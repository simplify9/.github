#!/usr/bin/env bash
# Sourced by action.yml (verify, flutter-android-build.yml, flutter-ios-build.yml) and test_flutter_version.sh.
# bash 3.2-safe: flutter-ios-build.yml sources it on macOS.

# pubspec_flutter <pubspec.yaml>: the environment.flutter value, quotes and a trailing comment removed
# (empty when there is none). Only the top-level `environment:` block counts.
pubspec_flutter() {
  [ -f "$1" ] || return 0
  awk '
    { sub(/\r$/, "") }
    /^[^ \t#]/ { env = ($0 ~ /^environment:[ \t]*(#.*)?$/); next }
    env && /^[ \t]+flutter:/ {
      v = $0
      sub(/^[ \t]+flutter:[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v); gsub(/["\047]/, "", v); sub(/[ \t]+$/, "", v)
      print v; exit
    }' "$1"
}

# flutter_version <dir> [explicit]: "<version> <source>". The caller's input wins; else an exact
# environment.flutter in <dir>/pubspec.yaml (the pin Renovate keeps current, with the lock); else 3.x.
flutter_version() {
  local pinned
  if [ -n "${2:-}" ]; then echo "$2 input"; return; fi
  pinned="$(pubspec_flutter "$1/pubspec.yaml")"
  if [[ "${pinned}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "${pinned} pubspec.yaml"; return; fi
  echo "3.x default"
}
