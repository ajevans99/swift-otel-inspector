#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
version=$(cat "$repo_root/VERSION")

base=${version%%+*}
build=
if [ "$base" != "$version" ]; then
    build=${version#*+}
    case "$build" in
        ""|*+*) echo "VERSION has an invalid build identifier: $version" >&2; exit 1 ;;
    esac
fi

core=${base%%-*}
prerelease=
if [ "$core" != "$base" ]; then
    prerelease=${base#*-}
    if [ -z "$prerelease" ]; then
        echo "VERSION has an empty prerelease identifier: $version" >&2
        exit 1
    fi
fi

if ! printf '%s\n' "$core" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
    echo "VERSION is not valid SemVer: $version" >&2
    exit 1
fi

if [ -n "$prerelease" ] && ! printf '%s\n' "$prerelease" | awk -F. '
    {
        for (i = 1; i <= NF; i++) {
            if ($i == "" || $i !~ /^[0-9A-Za-z-]+$/) exit 1
            if ($i ~ /^[0-9]+$/ && length($i) > 1 && substr($i, 1, 1) == "0") exit 1
        }
    }
'; then
    echo "VERSION has an invalid prerelease identifier: $version" >&2
    exit 1
fi

if [ -n "$build" ] && ! printf '%s\n' "$build" | awk -F. '
    {
        for (i = 1; i <= NF; i++) {
            if ($i == "" || $i !~ /^[0-9A-Za-z-]+$/) exit 1
        }
    }
'; then
    echo "VERSION has an invalid build identifier: $version" >&2
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
