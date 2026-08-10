#!/usr/bin/env bash
#
# install-docker.sh — Idempotent Docker installer for the MSP workshop.
#
# If Docker is already installed and the daemon is running, exits 0. If the
# daemon is reachable only with elevated privileges (current user is not in
# the 'docker' group), adds the user to the group and prints a re-login
# warning. Otherwise attempts to start the daemon (systemctl -> service)
# without reinstalling. If Docker is missing entirely, installs it for the
# current OS, starts the daemon, and ensures the current user can run docker
# without sudo.
#
# Supported: Linux (via the official get.docker.com convenience script) and
# macOS (via the Homebrew cask for Docker Desktop). Override the installer
# URL with: DOCKER_INSTALL_CHANNEL=<url>
#
# Usage:
#   ./install-docker.sh

set -euo pipefail

# ANSI colors for messages.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { printf "${GREEN}[install-docker]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[install-docker]${NC} %s\n" "$*" >&2; }
err() { printf "${RED}[install-docker]${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}[install-docker]${NC} %s\n" "$*"; }

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

is_root() {
  [[ "$(id -u)" -eq 0 ]]
}

# Run a command with sudo unless we are already root.
maybe_sudo() {
  if is_root; then
    "$@"
  else
    sudo "$@"
  fi
}

DEFAULT_DOCKER_INSTALL_CHANNEL="https://get.docker.com"
: "${DOCKER_INSTALL_CHANNEL:=${DEFAULT_DOCKER_INSTALL_CHANNEL}}"

docker_installed() {
  command_exists docker
}

docker_daemon_running() {
  docker info >/dev/null 2>&1
}

# Check the daemon with elevated privileges. Useful when the current user is
# not in the 'docker' group: the local 'docker info' will fail with a
# permission error, but the daemon itself may be running fine.
docker_daemon_running_privileged() {
  maybe_sudo docker info >/dev/null 2>&1
}

# Returns 0 if the systemd 'docker' service (or legacy 'service docker') is
# already active. Lets us distinguish "user lacks group membership" from
# "daemon is truly down" without trying to start anything.
docker_service_active() {
  if command_exists systemctl; then
    if maybe_sudo systemctl is-active docker >/dev/null 2>&1; then
      return 0
    fi
    return 1
  fi

  if command_exists service; then
    if maybe_sudo service docker status >/dev/null 2>&1; then
      return 0
    fi
  fi

  return 1
}

detect_os() {
  local os
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "${os}" in
    linux) printf 'linux\n' ;;
    darwin) printf 'darwin\n' ;;
    *)
      err "unsupported OS: ${os}. Only Linux and macOS are supported."
      return 1
      ;;
  esac
}

start_docker_service() {
  log "starting Docker daemon..."

  if command_exists systemctl; then
    info "  using systemctl..."
    if maybe_sudo systemctl start docker; then
      sleep 2 || true
      if docker_daemon_running_privileged; then
        return 0
      fi
    fi
  fi

  if command_exists service; then
    info "  using service..."
    if maybe_sudo service docker start; then
      sleep 2 || true
      if docker_daemon_running_privileged; then
        return 0
      fi
    fi
  fi

  return 1
}

# Returns 0 if the current user was newly added to the 'docker' group (so the
# caller should warn about re-login). Returns 1 if the user was already a
# member or the group could not be managed.
ensure_user_in_docker_group() {
  if ! getent group docker >/dev/null 2>&1; then
    info "creating 'docker' group..."
    maybe_sudo groupadd docker
  fi

  local current_user
  current_user="${USER:-$(id -un 2>/dev/null)}"
  if [[ -z "${current_user}" ]]; then
    warn "could not determine current user; skipping docker group management"
    return 1
  fi

  if id -nG "${current_user}" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
    return 1
  fi

  info "adding current user ('${current_user}') to the 'docker' group..."
  maybe_sudo usermod -aG docker "${current_user}"
  return 0
}

install_docker_linux() {
  if ! command_exists curl && ! command_exists wget; then
    err "neither curl nor wget is available; install one and re-run"
    return 1
  fi

  local fetcher
  if command_exists curl; then
    fetcher="curl -fsSL"
  else
    fetcher="wget -qO-"
  fi

  log "downloading Docker installer from ${DOCKER_INSTALL_CHANNEL}..."

  if is_root; then
    if ! sh -c "${fetcher} ${DOCKER_INSTALL_CHANNEL} | sh"; then
      err "Docker install script failed"
      return 1
    fi
  else
    if ! command_exists sudo; then
      err "this installer requires root privileges; re-run as root or install sudo"
      return 1
    fi
    if ! ${fetcher} "${DOCKER_INSTALL_CHANNEL}" | sudo sh; then
      err "Docker install script failed"
      return 1
    fi
  fi
}

install_docker_macos() {
  if ! command_exists brew; then
    err "Docker Desktop is required on macOS, but Homebrew is not installed"
    err "install Docker Desktop from: https://www.docker.com/products/docker-desktop"
    return 1
  fi

  log "installing Docker Desktop via Homebrew..."
  brew install --cask docker
}

print_relogin_warning() {
  echo
  warn "you were added to the 'docker' group."
  warn "log out and back in (or run 'newgrp docker') for the change to take effect"
  warn "in new shells. Existing shells must be restarted."
}

main() {
  for arg in "$@"; do
    case "${arg}" in
      -h|--help)
        cat <<EOF
Usage: $(basename "$0")

Environment:
  DOCKER_INSTALL_CHANNEL   URL of the Docker installer script
                           (default: https://get.docker.com)

Behavior:
  - If 'docker' is installed and 'docker info' succeeds, exits 0.
  - If 'docker' is installed but the daemon is not reachable by the current
    user, checks the daemon with elevated privileges: if the daemon (or its
    systemd unit) is already running, adds the user to the 'docker' group
    and prints a re-login warning. Otherwise starts the daemon via
    systemctl (or the legacy 'service' command).
  - If 'docker' is missing, installs it for the current OS, starts the
    daemon, and ensures the current user is in the 'docker' group.

Exit codes:
  0  success (installed, already present, or daemon started)
  1  unsupported OS or install/start failure
EOF
        exit 0
        ;;
      *)
        err "unknown argument: ${arg}"
        exit 1
        ;;
    esac
  done

  local os
  os="$(detect_os)"

  # Already installed -> check whether the daemon is actually usable.
  if docker_installed; then
    if docker_daemon_running; then
      log "Docker is already installed and the daemon is running"
      exit 0
    fi

    warn "Docker is installed but 'docker info' failed"

    if [[ "${os}" == "darwin" ]]; then
      err "on macOS, launch Docker Desktop and re-run this script"
      exit 1
    fi

    # Daemon may be running but the current user lacks group membership
    # (classic Strigo-lab scenario: 'docker info' fails with permission denied
    # while 'sudo docker info' and 'systemctl is-active docker' succeed).
    if docker_daemon_running_privileged || docker_service_active; then
      warn "Docker daemon is running, but the current user cannot access it"
      if ensure_user_in_docker_group; then
        print_relogin_warning
      else
        warn "could not add the current user to the 'docker' group automatically"
        warn "run 'sudo usermod -aG docker \$USER' and re-login"
      fi
      exit 0
    fi

    # Daemon is genuinely down: try systemctl, then legacy service.
    info "attempting to start the daemon..."
    if ! start_docker_service; then
      err "Docker is installed but the daemon failed to start"
      err "try 'sudo systemctl status docker' or 'journalctl -u docker'"
      exit 1
    fi
    log "Docker daemon started"

    if ensure_user_in_docker_group; then
      print_relogin_warning
    fi
    exit 0
  fi

  # Not installed -> install for the current OS.
  log "Docker not found; installing..."

  if [[ "${os}" == "darwin" ]]; then
    install_docker_macos
    warn "Docker Desktop has been installed. Launch it once to finish setup,"
    warn "then re-run this script so the daemon check can succeed."
    exit 0
  fi

  install_docker_linux

  if ! docker_installed; then
    err "installation completed but the 'docker' command is still not on PATH"
    err "open a new shell or check the installer output above"
    exit 1
  fi

  log "Docker has been installed"

  if ! docker_daemon_running; then
    if ! start_docker_service; then
      err "Docker was installed but the daemon failed to start"
      err "try 'sudo systemctl status docker' or check /var/log/dockerd.log"
      exit 1
    fi
  fi
  log "Docker daemon is running"

  if ensure_user_in_docker_group; then
    print_relogin_warning
  fi

  log "Docker is ready"
  docker version --format 'Client: {{.Client.Version}}{{"\n"}}Server: {{.Server.Version}}' 2>/dev/null || true
}

main "$@"
