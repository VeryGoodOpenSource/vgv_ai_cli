#!/usr/bin/env bash
# Installs the vgv_ai executable from a GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/VeryGoodOpenSource/vgv_ai_cli/main/tool/install.sh | bash
#
# VGV_AI_VERSION      Version to install, such as 0.1.0. Defaults to the latest release.
# VGV_AI_INSTALL_DIR  Directory to install into. Defaults to $HOME/.local/bin.
#
# Rerun it to upgrade in place.

set -euo pipefail

readonly repo="VeryGoodOpenSource/vgv_ai_cli"

fail() {
  echo "error: $*" >&2
  exit 1
}

require() {
  command -v "$1" > /dev/null || fail "$1 is required to install vgv_ai"
}

detect_os() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux) echo linux ;;
    *) fail "unsupported OS: $(uname -s). On Windows, use WSL" ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    arm64 | aarch64) echo arm64 ;;
    x86_64 | amd64) echo x64 ;;
    *) fail "unsupported architecture: $(uname -m)" ;;
  esac
}

# The newest release tagged vX.Y.Z, skipping the vgv_ai_plugins-vX.Y.Z releases.
latest_version() {
  local releases
  releases="$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=20")" ||
    fail "could not list the releases of $repo"
  printf '%s\n' "$releases" |
    sed -n 's/.*"tag_name": *"v\([0-9][^"]*\)".*/\1/p' |
    head -n 1
}

sha256() {
  if command -v sha256sum > /dev/null; then
    sha256sum "$1" | cut -d ' ' -f 1
  else
    shasum -a 256 "$1" | cut -d ' ' -f 1
  fi
}

main() {
  require curl
  require tar

  local os arch version
  os="$(detect_os)"
  arch="$(detect_arch)"
  version="${VGV_AI_VERSION:-$(latest_version)}"
  version="${version#v}"
  [ -n "$version" ] || fail "could not find a vgv_ai release"

  local install_dir="${VGV_AI_INSTALL_DIR:-$HOME/.local/bin}"
  local archive="vgv_ai-$version-$os-$arch.tar.gz"
  local url="https://github.com/$repo/releases/download/v$version/$archive"

  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064 # Expand now: tmp is local and gone by the time EXIT fires.
  trap "rm -rf '$tmp'" EXIT

  echo "Downloading vgv_ai $version for $os-$arch..."
  curl -fsSL "$url" -o "$tmp/$archive" || fail "could not download $url"
  curl -fsSL "$url.sha256" -o "$tmp/$archive.sha256" || fail "could not download $url.sha256"

  local expected actual
  expected="$(cut -d ' ' -f 1 < "$tmp/$archive.sha256")"
  actual="$(sha256 "$tmp/$archive")"
  [ "$expected" = "$actual" ] ||
    fail "checksum mismatch for $archive: expected $expected, got $actual"

  tar -xzf "$tmp/$archive" -C "$tmp"
  mkdir -p "$install_dir"
  mv -f "$tmp/vgv_ai" "$install_dir/vgv_ai"
  chmod 755 "$install_dir/vgv_ai"

  echo "Installed vgv_ai $version to $install_dir/vgv_ai"
  case ":$PATH:" in
    *":$install_dir:"*) ;;
    *) echo "warning: $install_dir is not on your PATH. Add it to run vgv_ai." >&2 ;;
  esac
}

main "$@"
