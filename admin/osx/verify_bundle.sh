#!/bin/bash
# SPDX-FileCopyrightText: 2026 Files365 contributors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Verifies that a built .app bundle is actually loadable on a machine that is
# not the build machine.
#
# Usage: verify_bundle.sh <path to .app> [--universal]
#
# This exists because the failure it checks for is completely silent: a bundle
# missing one of the client's own dylibs, or shipping a binary whose
# dependencies still point into /opt/homebrew or the build tree, compiles,
# packages, signs, uploads and installs without a single error, then aborts on
# the user's machine at launch with "dyld: Library not loaded".  Checked here so
# that CI fails instead of a release.
#
# Scope is the Mach-O files the build itself produces - the executables in
# Contents/MacOS and the private dylibs they pull in from Contents/Frameworks.
# Qt's own inter-framework graph is macdeployqt's business and is already proven
# by any bundle that launches at all, so walking into it here would buy nothing
# but false alarms.

set -uo pipefail

app=${1:-}
mode=${2:-}

if [ -z "$app" ] || [ ! -d "$app" ]; then
    echo "usage: $0 <path to .app> [--universal]" >&2
    exit 2
fi

# Resolved to an absolute, symlink-free path up front: every path below is
# compared against it to decide whether a dependency stays inside the bundle,
# and that comparison is only meaningful if both sides are normalised the same
# way.  Left as given, a relative argument would make every dependency reached
# through an @loader_path-relative RPATH look like it points outside.
app=$(cd "${app%/}" && pwd -P) || exit 2
macos_dir="$app/Contents/MacOS"
failures=0

fail() {
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}

# otool repeats its output once per architecture slice, so every read of it here
# is deduplicated.  It also labels each slice with a header line - "<path>:" for
# a thin file, "<path> (architecture arm64):" for each slice of a fat one - and
# those are dropped by matching the trailing colon, which no dependency path or
# install name ever ends in.  Skipping a fixed number of leading lines instead
# would leave every slice header after the first looking like a dependency on
# the file's own absolute build-machine path: a false positive that shows up
# only on universal binaries, which is to say only after the lipo merge.
strip_slice_headers() {
    grep -v ':$'
}

deps_of() {
    otool -L "$1" | strip_slice_headers | awk '{print $1}' | sort -u
}

rpaths_of() {
    otool -l "$1" | awk '/LC_RPATH/ {found = 1} found && /^ *path / {print $2; found = 0}' | sort -u
}

own_id_of() {
    # Empty for executables, which have no LC_ID_DYLIB.
    otool -D "$1" | strip_slice_headers | head -1
}

# Collapses the ".." segments that come from expanding an RPATH such as
# @loader_path/../Frameworks, so that both the in-bundle test and the paths
# printed in CI logs read as real locations.
normalize_path() {
    local dir base
    dir=$(dirname "$1")
    base=$(basename "$1")
    ( cd "$dir" 2>/dev/null && echo "$(pwd -P)/$base" ) || echo "$1"
}

# Prints the on-disk path a dependency string resolves to, or nothing if it
# resolves nowhere.  @loader_path is relative to the binary holding the
# reference; @executable_path is relative to the bundle's main executable
# directory; @rpath is tried against each of the binary's own LC_RPATH entries,
# which are themselves usually @loader_path- or @executable_path-relative.
resolve_dep() {
    local dep=$1 binary=$2
    local loader_path
    loader_path=$(dirname "$binary")

    case "$dep" in
        @rpath/*)
            local suffix=${dep#@rpath/} rpath candidate
            while IFS= read -r rpath; do
                [ -n "$rpath" ] || continue
                candidate=${rpath//@loader_path/$loader_path}
                candidate=${candidate//@executable_path/$macos_dir}
                if [ -e "$candidate/$suffix" ]; then
                    normalize_path "$candidate/$suffix"
                    return 0
                fi
            done <<< "$(rpaths_of "$binary")"
            ;;
        @loader_path/*|@executable_path/*)
            local candidate=${dep//@loader_path/$loader_path}
            candidate=${candidate//@executable_path/$macos_dir}
            [ -e "$candidate" ] && normalize_path "$candidate"
            ;;
        /*)
            [ -e "$dep" ] && echo "$dep"
            ;;
    esac
}

# A dependency is acceptable only if it is part of the OS or resolves to a file
# inside the bundle.  An absolute path that happens to exist on this machine
# (any Homebrew prefix, any path in the build tree) is the exact defect being
# looked for, so it is rejected even though it resolves here.
check_binary() {
    local binary=$1 own_id dep resolved
    own_id=$(own_id_of "$binary")

    while IFS= read -r dep; do
        [ -n "$dep" ] || continue
        # A dylib's first entry is its own install name, not a dependency.
        [ "$dep" = "$own_id" ] && continue

        case "$dep" in
            /usr/lib/*|/System/*)
                continue
                ;;
            /*)
                fail "${binary#"$app"/} depends on the absolute path $dep, which exists only on the build machine"
                continue
                ;;
        esac

        resolved=$(resolve_dep "$dep" "$binary")
        if [ -z "$resolved" ]; then
            fail "${binary#"$app"/} depends on $dep, which resolves to nothing inside the bundle"
        elif [ "${resolved#"$app"/}" = "$resolved" ]; then
            fail "${binary#"$app"/} depends on $dep, which resolves outside the bundle to $resolved"
        fi
    done <<< "$(deps_of "$binary")"
}

check_universal() {
    local binary=$1 arches
    arches=$(lipo -info "$binary" 2>/dev/null)
    case "$arches" in
        *x86_64*arm64*|*arm64*x86_64*) ;;
        *) fail "${binary#"$app"/} is not universal: ${arches#*: }" ;;
    esac
}

# The executables, plus every private dylib they load out of the bundle.  The
# dylib list is derived from the executables' own @rpath references rather than
# hardcoded, so it stays correct under rebranding (APPLICATION_EXECUTABLE feeds
# the dylib names) and catches a missing one as an unresolved dependency above.
binaries=()
while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    file "$candidate" | grep -q "Mach-O" && binaries+=("$candidate")
done <<< "$(find "$macos_dir" -type f -not -type l 2>/dev/null)"

# Bailing out rather than accumulating: with nothing to inspect every check
# below would pass vacuously, and an empty array is an unbound expansion under
# set -u on the bash 3.2 that ships with macOS.
if [ ${#binaries[@]} -eq 0 ]; then
    fail "no Mach-O executable found in Contents/MacOS"
    exit 1
fi

private_dylibs=()
for binary in "${binaries[@]}"; do
    while IFS= read -r dep; do
        case "$dep" in
            @rpath/lib*sync.*.dylib) ;;
            *) continue ;;
        esac
        resolved=$(resolve_dep "$dep" "$binary")
        if [ -n "$resolved" ]; then
            private_dylibs+=("$resolved")
        else
            fail "${binary#"$app"/} needs $dep, which was never deployed into Contents/Frameworks"
        fi
    done <<< "$(deps_of "$binary")"
done

if [ ${#private_dylibs[@]} -gt 0 ]; then
    while IFS= read -r dylib; do
        binaries+=("$dylib")
    done <<< "$(printf '%s\n' "${private_dylibs[@]}" | sort -u)"
fi

for binary in "${binaries[@]}"; do
    echo "checking ${binary#"$app"/}"
    check_binary "$binary"
    [ "$mode" = "--universal" ] && check_universal "$binary"
done

if [ "$failures" -ne 0 ]; then
    echo "$failures problem(s) found in $app" >&2
    exit 1
fi

echo "OK: $app is self-contained"
