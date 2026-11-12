#!/usr/bin/env bash
set -Eeuo pipefail

# Bootstrap Git and Miniforge on an Ubuntu VM.
# Run as your regular user (sudo access required for apt).

if [[ "${EUID}" -eq 0 ]]; then
  echo 'Please run this script as your regular user, not root.' >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo 'This script requires Ubuntu/Debian with apt-get.' >&2
  exit 1
fi

sudo apt-get update
sudo apt-get install -y git curl wget ca-certificates bzip2

INSTALL_DIR="${MINIFORGE_DIR:-$HOME/miniforge3}"
if [[ ! -x "$INSTALL_DIR/bin/conda" ]]; then
  case "$(uname -m)" in
    x86_64|aarch64|ppc64le) ARCH="$(uname -m)" ;;
    *) echo "Unsupported Miniforge architecture: $(uname -m)" >&2; exit 1 ;;
  esac

  installer="$(mktemp --suffix=.sh)"
  trap 'rm -f "$installer"' EXIT
  url="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-${ARCH}.sh"
  echo "Downloading Miniforge: $url"
  curl --fail --location --retry 3 --output "$installer" "$url"
  bash "$installer" -b -p "$INSTALL_DIR"
  rm -f "$installer"
  trap - EXIT
else
  echo "Using existing Miniforge installation at $INSTALL_DIR"
fi

"$INSTALL_DIR/bin/conda" init bash
"$INSTALL_DIR/bin/conda" config --set channel_priority strict
"$INSTALL_DIR/bin/conda" config --set auto_activate_base false

printf '\nInstallation complete.\n'
"$INSTALL_DIR/bin/conda" --version
git --version
printf '\nTo use conda in your current shell, run:\n  source ~/.bashrc\n'
printf 'Then run your Archiver Appliance installer.\n'
