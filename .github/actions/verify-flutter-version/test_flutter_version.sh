#!/usr/bin/env bash
# Truth table for flutter_version.sh. Run: bash test_flutter_version.sh (and /bin/bash on a Mac).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=flutter_version.sh
source "${here}/flutter_version.sh"
fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: want [$2] got [$3]"; fails=$((fails + 1)); fi; }
repo() { local d; d="$(mktemp -d)"; printf '%b' "$1" > "${d}/pubspec.yaml"; echo "${d}"; }
DEPS='dependencies:\n  flutter:\n    sdk: flutter\n'

eq explicit_wins "3.44.1 input" "$(flutter_version "$(repo "environment:\n  sdk: ^3.9.0\n  flutter: 3.50.0\n")" 3.44.1)"
eq pinned "3.50.0 pubspec.yaml" "$(flutter_version "$(repo "name: app\nenvironment:\n  sdk: \">=3.3.2 <4.0.0\"\n  flutter: 3.50.0\n${DEPS}")")"
eq pinned_quoted_commented "3.50.0 pubspec.yaml" "$(flutter_version "$(repo "environment:\n  flutter: \"3.50.0\" # Renovate keeps this current\n  sdk: ^3.9.0\n")")"
eq pinned_single_quotes_crlf "3.47.9 pubspec.yaml" "$(flutter_version "$(repo "environment:\r\n  flutter: '3.47.9'\r\n")")"
eq range_is_not_a_pin "3.x default" "$(flutter_version "$(repo "environment:\n  flutter: \">=3.27.0\"\n")")"
eq caret_is_not_a_pin "3.x default" "$(flutter_version "$(repo "environment:\n  flutter: ^3.50.0\n")")"
eq no_flutter_key "3.x default" "$(flutter_version "$(repo "environment:\n  sdk: \">=3.3.2 <4.0.0\"\n${DEPS}")")"
# `flutter:` under dependencies (the SDK dependency) or a later top-level key is not the pin.
eq dependency_flutter_ignored "3.x default" "$(flutter_version "$(repo "environment:\n  sdk: ^3.9.0\n${DEPS}flutter:\n  uses-material-design: true\n")")"
eq no_pubspec "3.x default" "$(flutter_version "$(mktemp -d)")"
# macOS runners (flutter-ios-build.yml) source this with /bin/bash 3.2: no bash 4 syntax.
eq bash32_safe "" "$(grep -nE '\$\{[A-Za-z_]+(,,?|\^\^?)\}|mapfile|readarray|declare -A|local -A' "${here}/flutter_version.sh")"

if [ "${fails}" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
