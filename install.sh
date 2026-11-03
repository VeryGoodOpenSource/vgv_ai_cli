#!/usr/bin/env bash
# Installs the prebuilt vgv_ai binary for this machine from GitHub Releases.
#
#   curl -fsSL https://raw.githubusercontent.com/VeryGoodOpenSource/vgv_ai_cli/main/install.sh | bash
#
# Options, passed after `bash -s --` when piping, or set in the environment:
#
#   --install-dir <dir>   VGV_AI_INSTALL_DIR   Where to put vgv_ai.
#                                              Defaults to ~/.local/bin.
#   --version <version>   VGV_AI_VERSION       The release to install, such as
#                                              0.2.0. Defaults to the latest.
#
# Running it again updates vgv_ai in place. macOS and Linux, on arm64 or x64,
# are supported. On Windows, use WSL.
set -euo pipefail

REPOSITORY="VeryGoodOpenSource/vgv_ai_cli"
EXECUTABLE="vgv_ai"

install_dir="${VGV_AI_INSTALL_DIR:-${HOME:?HOME is not set}/.local/bin}"
version="${VGV_AI_VERSION:-latest}"

fail() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat <<EOF_USAGE
Installs the prebuilt ${EXECUTABLE} binary for this machine.

Options:
  --install-dir <dir>  Where to put ${EXECUTABLE}, ~/.local/bin by default.
                       Or set VGV_AI_INSTALL_DIR.
  --version <version>  The release to install, such as 0.2.0, the latest by
                       default. Or set VGV_AI_VERSION.
  -h, --help           Show this help.
EOF_USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --install-dir)
      [ $# -ge 2 ] || fail "--install-dir needs a directory"
      install_dir="$2"
      shift 2
      ;;
    --version)
      [ $# -ge 2 ] || fail "--version needs a version"
      version="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

case "$(uname -s)" in
  Darwin) os="macos" ;;
  Linux) os="linux" ;;
  *) fail "$(uname -s) is not supported. vgv_ai runs on macOS and Linux; on Windows, use WSL." ;;
esac

case "$(uname -m)" in
  arm64 | aarch64) arch="arm64" ;;
  x86_64 | amd64) arch="x64" ;;
  *) fail "$(uname -m) is not supported. vgv_ai runs on arm64 and x64." ;;
esac

# A shell running under Rosetta reports x86_64 on Apple silicon. Prefer the
# native binary there.
if [ "$os" = "macos" ] && [ "$arch" = "x64" ] &&
  [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" = "1" ]; then
  arch="arm64"
fi

if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | cut -d ' ' -f 1; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
else
  fail "sha256sum or shasum is needed to verify the download"
fi

command -v curl >/dev/null 2>&1 || fail "curl is needed to download vgv_ai"
command -v tar >/dev/null 2>&1 || fail "tar is needed to unpack vgv_ai"

archive="${EXECUTABLE}-${os}-${arch}.tar.gz"
if [ "$version" = "latest" ]; then
  base_url="https://github.com/${REPOSITORY}/releases/latest/download"
else
  base_url="https://github.com/${REPOSITORY}/releases/download/v${version#v}"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "Downloading ${archive} (${version})..."
curl -fsSL --retry 3 -o "${tmp_dir}/${archive}" "${base_url}/${archive}" ||
  fail "could not download ${base_url}/${archive}"
curl -fsSL --retry 3 -o "${tmp_dir}/${archive}.sha256" "${base_url}/${archive}.sha256" ||
  fail "could not download ${base_url}/${archive}.sha256"

expected="$(cut -d ' ' -f 1 <"${tmp_dir}/${archive}.sha256")"
actual="$(sha256 "${tmp_dir}/${archive}")"
[ -n "$expected" ] && [ "$expected" = "$actual" ] ||
  fail "checksum mismatch for ${archive}: expected ${expected}, got ${actual}"

tar -xzf "${tmp_dir}/${archive}" -C "$tmp_dir"
[ -f "${tmp_dir}/${EXECUTABLE}" ] || fail "${archive} does not contain ${EXECUTABLE}"

mkdir -p "$install_dir" 2>/dev/null ||
  fail "could not create ${install_dir}. Choose another directory with --install-dir."
[ -w "$install_dir" ] ||
  fail "${install_dir} is not writable. Choose another directory with --install-dir."

# Rename into place from the same directory, rather than writing over the old
# file, so a running vgv_ai, such as the one suggesting this update, keeps its
# own copy.
staged="${install_dir}/.${EXECUTABLE}.$$"
cp "${tmp_dir}/${EXECUTABLE}" "$staged"
chmod +x "$staged"
mv -f "$staged" "${install_dir}/${EXECUTABLE}"

installed_version="$("${install_dir}/${EXECUTABLE}" --version 2>/dev/null | head -n 1 || true)"
echo "Installed ${EXECUTABLE} ${installed_version} to ${install_dir}/${EXECUTABLE}"

case ":${PATH}:" in
  *":${install_dir}:"*) ;;
  *)
    echo
    echo "${install_dir} is not on your PATH. Add it to your shell profile:"
    echo
    echo "  export PATH=\"${install_dir}:\$PATH\""
    ;;
esac

echo
echo "Run '${EXECUTABLE} --help' to get started."
