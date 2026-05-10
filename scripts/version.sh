#!/usr/bin/env bash
set -euo pipefail

PUBSPEC="pubspec.yaml"

usage() {
  cat <<'USAGE'
Usage:
  scripts/version.sh show
  scripts/version.sh bump-build
  scripts/version.sh bump-patch
  scripts/version.sh bump-minor
  scripts/version.sh bump-major
  scripts/version.sh set <major.minor.patch[+build]>

Notes:
  - App Store marketing version is major.minor.patch.
  - Build number is the value after + and must increase for each upload.
USAGE
}

if [ ! -f "${PUBSPEC}" ]; then
  echo "pubspec.yaml not found. Run from project root." >&2
  exit 1
fi

current_version() {
  awk '/^version: / {print $2; exit}' "${PUBSPEC}"
}

write_version() {
  local next="$1"
  perl -0pi -e "s/^version: .*\$/version: ${next}/m" "${PUBSPEC}"
}

split_version() {
  local raw="$1"
  name="${raw%%+*}"
  if [[ "${raw}" == *"+"* ]]; then
    build="${raw##*+}"
  else
    build="1"
  fi
  IFS='.' read -r major minor patch <<<"${name}"
  if [[ ! "${major}" =~ ^[0-9]+$ || ! "${minor}" =~ ^[0-9]+$ || ! "${patch}" =~ ^[0-9]+$ || ! "${build}" =~ ^[0-9]+$ ]]; then
    echo "Invalid pubspec version: ${raw}" >&2
    exit 1
  fi
}

cmd="${1:-show}"
raw="$(current_version)"
split_version "${raw}"

case "${cmd}" in
  show)
    echo "${raw}"
    ;;
  bump-build)
    build=$((build + 1))
    next="${major}.${minor}.${patch}+${build}"
    write_version "${next}"
    echo "${next}"
    ;;
  bump-patch)
    patch=$((patch + 1))
    next="${major}.${minor}.${patch}+1"
    write_version "${next}"
    echo "${next}"
    ;;
  bump-minor)
    minor=$((minor + 1))
    patch=0
    next="${major}.${minor}.${patch}+1"
    write_version "${next}"
    echo "${next}"
    ;;
  bump-major)
    major=$((major + 1))
    minor=0
    patch=0
    next="${major}.${minor}.${patch}+1"
    write_version "${next}"
    echo "${next}"
    ;;
  set)
    next="${2:-}"
    if [[ ! "${next}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?$ ]]; then
      echo "Invalid version: ${next}" >&2
      usage >&2
      exit 1
    fi
    if [[ "${next}" != *"+"* ]]; then
      next="${next}+1"
    fi
    write_version "${next}"
    echo "${next}"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
