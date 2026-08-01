#!/usr/bin/env bash
set -eu

usage() {
  printf 'usage: share-safe.sh <html-file>\n'
}

if [ "${1:-}" = --help ]; then
  usage
  exit 0
fi

if [ "$#" -ne 1 ]; then
  usage >&2
  exit 2
fi

if ! command -v lavish-axi >/dev/null 2>&1; then
  printf 'share-safe: lavish-axi is unavailable\n' >&2
  exit 1
fi

if ! share_output=$(lavish-axi share "$1" 2>&1); then
  printf 'share-safe: publishing failed; inspect Lavish locally\n' >&2
  exit 1
fi

url=$(printf '%s\n' "$share_output" | sed -n 's/^[[:space:]]*url: //p' | head -n 1)
case "$url" in
  http://*|https://*) ;;
  *)
    printf 'share-safe: publishing returned no valid URL\n' >&2
    exit 1
    ;;
esac
case "$url" in
  *[[:space:]]*)
    printf 'share-safe: publishing returned no valid URL\n' >&2
    exit 1
    ;;
esac

printf '%s\n' "$url"
