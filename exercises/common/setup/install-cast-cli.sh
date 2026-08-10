#!/usr/bin/env bash
#
# install-cast-cli.sh — Idempotent cast-cli installer for the MSP workshop.
#
# Checks for cast-cli; if absent, installs it via get.cast.ai/linux, ensures
# the binary is exposed as `cast-cli` (the installer ships it as `castctl`),
# and places it on PATH.
#
# Usage:
#   ./install-cast-cli.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { printf "${GREEN}[install-cast-cli]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[install-cast-cli]${NC} %s\n" "$*" >&2; }
err() { printf "${RED}[install-cast-cli]${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}[install-cast-cli]${NC} %s\n" "$*"; }

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Return a writable directory suitable for binaries.
install_dir() {
  if [[ -w /usr/local/bin ]]; then
    printf '/usr/local/bin\n'
  else
    printf '%s/.local/bin\n' "${HOME}"
  fi
}

# Ensure the given directory is on PATH for the rest of this script.
ensure_path() {
  local dir="$1"
  case ":${PATH}:" in
    *":${dir}:"*) ;;
    *)
      export PATH="${dir}:${PATH}"
      info "added ${dir} to PATH for this session"
      info "to persist, add: export PATH=\"${dir}:\$PATH\" to your shell profile"
      ;;
  esac
}

# Print the cast-cli version string. The upstream binary currently
# exposes `cast-cli version` as the reliable invocation.
cast_cli_version() {
  local v
  v="$(cast-cli version 2>/dev/null || true)"
  if [[ -n "${v}" ]]; then
    printf '%s' "${v}"
    return 0
  fi
  v="$(cast-cli --version 2>/dev/null || true)"
  if [[ -n "${v}" ]]; then
    printf '%s' "${v}"
    return 0
  fi
  v="$(cast-cli --help 2>/dev/null | head -n1 || true)"
  if [[ -n "${v}" ]]; then
    printf '%s' "${v}"
    return 0
  fi
  printf ''
}

install_cast_cli() {
  local version_output install_ok target_dir use_sudo
  local candidate found castctl_path castctl_dir

  if command_exists cast-cli; then
    version_output="$(cast_cli_version)"
    if [[ -n "${version_output}" ]]; then
      log "cast-cli: found, skipping (${version_output})"
    else
      log "cast-cli: found, skipping"
    fi
    return 0
  fi

  log "cast-cli: not found, installing via get.cast.ai/linux..."

  if ! curl -fsSL https://get.cast.ai/linux | bash; then
    err "failed to install cast-cli via get.cast.ai/linux" >&2
    return 1
  fi

  # The cast.ai installer ships the binary as `castctl`. Expose it as
  # `cast-cli` as well so the documented command name works everywhere.
  if ! command_exists cast-cli && command_exists castctl; then
    castctl_path="$(command -v castctl)"
    castctl_dir="$(dirname "${castctl_path}")"
    if [[ -w "${castctl_dir}" ]]; then
      ln -sf "${castctl_path}" "${castctl_dir}/cast-cli"
    else
      sudo -n ln -sf "${castctl_path}" "${castctl_dir}/cast-cli" 2>/dev/null || true
    fi
  fi

  # Re-check before searching the filesystem.
  if command_exists cast-cli; then
    version_output="$(cast_cli_version)"
    if [[ -n "${version_output}" ]]; then
      log "cast-cli installed: ${version_output}"
    else
      log "cast-cli installed"
    fi
    return 0
  fi

  # Installer did not place cast-cli on PATH. Search known locations.
  warn "cast-cli: not on PATH after installer; searching known locations..."

  found=""
  for candidate in \
      "${HOME}/.castai/bin/cast-cli" \
      "${HOME}/.castai/bin/castctl" \
      "${HOME}/.castai/cast-cli" \
      "${HOME}/.castai/castctl" \
      "${HOME}/.local/bin/cast-cli" \
      "${HOME}/.local/bin/castctl" \
      "/usr/local/bin/cast-cli" \
      "/usr/local/bin/castctl" \
      "/usr/bin/cast-cli" \
      "/usr/bin/castctl"; do
    if [[ -x "${candidate}" ]]; then
      found="${candidate}"
      break
    fi
  done

  if [[ -z "${found}" ]]; then
    err "cast-cli installer finished but binary not found in known locations" >&2
    return 1
  fi

  target_dir="$(install_dir)"
  use_sudo=0
  if [[ ! -w "${target_dir}" ]] && command_exists sudo; then
    use_sudo=1
  fi

  install_ok=0
  mkdir -p "${target_dir}"
  if [[ "${use_sudo}" == "1" ]]; then
    if sudo -n install -m 0755 "${found}" "${target_dir}/cast-cli" 2>/dev/null; then
      install_ok=1
    fi
  else
    if install -m 0755 "${found}" "${target_dir}/cast-cli" 2>/dev/null; then
      install_ok=1
    fi
  fi

  if [[ "${install_ok}" -ne 1 ]]; then
    warn "cast-cli: install into ${target_dir} failed; falling back to ${HOME}/.local/bin"
    target_dir="${HOME}/.local/bin"
    mkdir -p "${target_dir}"
    if ! install -m 0755 "${found}" "${target_dir}/cast-cli"; then
      err "failed to place cast-cli on PATH (tried /usr/local/bin and ${target_dir})" >&2
      return 1
    fi
  fi

  ensure_path "${target_dir}"

  version_output="$(cast_cli_version)"
  if [[ -n "${version_output}" ]]; then
    log "cast-cli installed: ${version_output}"
  else
    log "cast-cli installed"
  fi
}

main() {
  install_cast_cli
  log "cast-cli setup complete"
}

main "$@"
