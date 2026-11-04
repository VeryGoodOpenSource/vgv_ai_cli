#!/usr/bin/env bash
# Points a Homebrew formula at the release archives of another version.
#
#   tool/update_homebrew_formula.sh <formula.rb> <version> <checksums-dir>
#
# Rewrites the formula in place: a `version` line, and each `url` line naming a
# <formula>-<version>-<os>-<arch>.tar.gz archive together with the `sha256` line after it. The
# checksum comes from that archive's .sha256 file in <checksums-dir>. Every other line, such as
# desc, caveats and test, is left as written.

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <formula.rb> <version> <checksums-dir>" >&2
  exit 64
fi

formula="$1"
version="${2#v}"
checksums="$3"
name="$(basename "$formula" .rb)"
updated="$(mktemp)"
trap 'rm -f "$updated"' EXIT

awk -v name="$name" -v version="$version" -v checksums="$checksums" '
  function fail(message) {
    print "error: " message > "/dev/stderr"
    failed = 1
    exit 1
  }

  function checksum(artifact,    file, line, fields) {
    file = checksums "/" artifact ".sha256"
    if ((getline line < file) <= 0) fail("no checksum file " file)
    close(file)
    split(line, fields, " ")
    return fields[1]
  }

  /^[[:space:]]*version "/ {
    sub(/"[^"]*"/, "\"" version "\"")
  }

  /^[[:space:]]*url "/ && match($0, name "-[^\"/]+-(macos|linux)-(arm64|x64)[.]tar[.]gz") {
    match($0, /(macos|linux)-(arm64|x64)[.]tar[.]gz/)
    artifact = name "-" version "-" substr($0, RSTART, RLENGTH)

    match($0, /"[^"]*\/releases\/download\//)
    base = substr($0, RSTART + 1, RLENGTH - 1)
    sub(/"[^"]*"/, "\"" base "v" version "/" artifact "\"")

    if (pending != "") fail("no sha256 line after the url for " previous)
    pending = checksum(artifact)
    previous = artifact
    urls++
    print
    next
  }

  /^[[:space:]]*sha256 "/ && pending != "" {
    sub(/"[^"]*"/, "\"" pending "\"")
    pending = ""
  }

  { print }

  END {
    if (failed) exit 1
    if (pending != "") fail("no sha256 line after the url for " previous)
    if (urls == 0) fail("no url names a " name " release archive")
  }
' "$formula" > "$updated"

cat "$updated" > "$formula"
