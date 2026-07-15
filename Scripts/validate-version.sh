#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
version=$(tr -d '[:space:]' < "$repo_root/VERSION")

if ! printf '%s\n' "$version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'; then
    echo "VERSION is not valid SemVer: $version" >&2
    exit 1
fi

declared_version=$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' \
    "$repo_root/Sources/InspectorCore/InspectorCore.swift")

if [ "$version" != "$declared_version" ]; then
    echo "VERSION ($version) does not match InspectorCore.version ($declared_version)" >&2
    exit 1
fi

if [ "${GITHUB_REF_TYPE:-}" = "tag" ] && [ "${GITHUB_REF_NAME:-}" != "v$version" ]; then
    echo "Tag ${GITHUB_REF_NAME:-} does not match v$version" >&2
    exit 1
fi

echo "Validated version $version"
