#!/usr/bin/env sh
set -eu

version="latest"
repo="becomeless/cc-x"
install_dir="${CCX_INSTALL_DIR:-$HOME/.local/bin}"
verify_checksum=1
uninstall=0

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Options:
  --version <version>       Install a specific version or tag. Default: latest
  --install-dir <dir>       Install directory. Default: $HOME/.local/bin
  --repo <owner/name>       GitHub repository. Default: becomeless/cc-x
  --no-checksum             Skip checksum verification
  --uninstall               Remove xx from the install directory
  -h, --help                Show this help
EOF
}

need_arg() {
  if [ "$#" -lt 2 ]; then
    echo "Missing value for $1" >&2
    exit 2
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      need_arg "$@"
      version="$2"
      shift 2
      ;;
    --install-dir)
      need_arg "$@"
      install_dir="$2"
      shift 2
      ;;
    --repo)
      need_arg "$@"
      repo="$2"
      shift 2
      ;;
    --no-checksum)
      verify_checksum=0
      shift
      ;;
    --uninstall)
      uninstall=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

download() {
  url="$1"
  out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$url" -O "$out"
  else
    echo "curl or wget is required." >&2
    exit 1
  fi
}

effective_url() {
  url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o /dev/null -w '%{url_effective}' "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qS --max-redirect=5 "$url" -O /dev/null 2>&1 | awk '/^  Location: / { loc=$2 } END { gsub(/\r/, "", loc); print loc }'
  else
    echo "curl or wget is required." >&2
    exit 1
  fi
}

sha256_file() {
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    return 1
  fi
}

resolve_tag() {
  requested="$1"
  if [ "$requested" = "latest" ]; then
    final="$(effective_url "https://github.com/$repo/releases/latest")"
    tag="${final##*/}"
    if [ -z "$tag" ] || [ "$tag" = "latest" ]; then
      echo "Could not resolve latest release tag." >&2
      exit 1
    fi
    printf '%s\n' "$tag"
  else
    case "$requested" in
      v*) printf '%s\n' "$requested" ;;
      *) printf 'v%s\n' "$requested" ;;
    esac
  fi
}

platform() {
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m | tr '[:upper:]' '[:lower:]')"

  case "$os" in
    darwin|linux) ;;
    *)
      echo "Unsupported OS: $os. Use npm install -g @cc-x/cc-x for this platform." >&2
      exit 1
      ;;
  esac

  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *)
      echo "Unsupported architecture: $arch. Use npm install -g @cc-x/cc-x for this platform." >&2
      exit 1
      ;;
  esac

  printf '%s_%s\n' "$os" "$arch"
}

if [ "$uninstall" -eq 1 ]; then
  rm -f "$install_dir/xx" \
    "$install_dir/presets.json" \
    "$install_dir/LICENSE" \
    "$install_dir/README.md" \
    "$install_dir/README.en.md"
  rmdir "$install_dir" 2>/dev/null || true
  echo "Removed ccx native install from $install_dir"
  exit 0
fi

tag="$(resolve_tag "$version")"
version_value="${tag#v}"
plat="$(platform)"
asset="ccx_${version_value}_${plat}.tar.gz"
base_url="https://github.com/$repo/releases/download/$tag"
tmp="${TMPDIR:-/tmp}/ccx-install-$$"

mkdir -p "$tmp"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

archive="$tmp/$asset"
download "$base_url/$asset" "$archive"

if [ "$verify_checksum" -eq 1 ]; then
  checksums="$tmp/checksums.txt"
  if download "$base_url/checksums.txt" "$checksums"; then
    expected="$(awk -v name="$asset" '$2 == name { print $1 }' "$checksums")"
    if [ -n "$expected" ]; then
      actual="$(sha256_file "$archive" || true)"
      if [ -z "$actual" ]; then
        echo "No sha256 tool found; skipping checksum verification." >&2
      elif [ "$actual" != "$expected" ]; then
        echo "Checksum mismatch for $asset" >&2
        exit 1
      fi
    else
      echo "Checksum entry for $asset was not found; skipping verification." >&2
    fi
  else
    echo "checksums.txt was not found; skipping verification." >&2
  fi
fi

tar -xzf "$archive" -C "$tmp"
src_dir="$tmp/ccx_${version_value}_${plat}"
if [ ! -f "$src_dir/xx" ]; then
  echo "Downloaded asset did not contain an xx binary." >&2
  exit 1
fi

mkdir -p "$install_dir"
cp "$src_dir/xx" "$install_dir/xx"
chmod 0755 "$install_dir/xx"
for name in presets.json LICENSE README.md README.en.md; do
  if [ -f "$src_dir/$name" ]; then
    cp "$src_dir/$name" "$install_dir/$name"
  fi
done

reported="$("$install_dir/xx" --version)"
echo "ccx $reported installed to $install_dir"
case ":$PATH:" in
  *":$install_dir:"*) ;;
  *)
    echo "Add $install_dir to PATH, then run: xx --version"
    ;;
esac
