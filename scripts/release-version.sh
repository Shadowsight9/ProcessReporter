#!/bin/bash
set -euo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"
output_file="${GITHUB_OUTPUT:-}"

if [[ ! "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?)$ ]]; then
  echo "Unsupported release tag: $tag" >&2
  echo "Expected a tag such as v1.6.0 or v1.6.0-beta.1" >&2
  exit 1
fi

marketing_version="${BASH_REMATCH[1]}"
build_number="$(git rev-list --count HEAD)"

if [[ -n "$output_file" ]]; then
  echo "marketing_version=$marketing_version" >> "$output_file"
  echo "build_number=$build_number" >> "$output_file"
  echo "release_tag=$tag" >> "$output_file"
else
  printf 'marketing_version=%s\n' "$marketing_version"
  printf 'build_number=%s\n' "$build_number"
  printf 'release_tag=%s\n' "$tag"
fi

echo "Release version: $marketing_version ($build_number)" >&2
