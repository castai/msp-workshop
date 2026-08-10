#!/usr/bin/env bash
#
# validate-setup.sh — Idempotent validator for the workshop prerequisites.
#
# Ensures that the CLIs required by the rest of the workshop (kubectl, helm,
# cast-cli) are installed and on PATH, and configures the k=kubectl alias.
#
# This script is the complete, idempotent validator for the workshop.
# It checks for kubectl, helm, and cast-cli, installs any that are missing,
# configures the k=kubectl alias, and prints a final pass/fail summary.
#
# Usage:
#   ./validate-setup.sh

set -euo pipefail

# Print a message prefixed with the script's tag so output is easy to grep.
log() {
  printf '[validate-setup] %s\n' "$*"
}

# Returns 0 if the given command is on PATH, non-zero otherwise.
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Detect the CPU architecture and print the value the upstream installers
# expect (e.g. "amd64", "arm64"). Fails with a clear message on stderr for
# any architecture the workshop does not support.
detect_arch() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64)
      printf 'amd64\n'
      ;;
    aarch64 | arm64)
      printf 'arm64\n'
      ;;
    *)
      printf 'error: unsupported architecture %s. Only x86_64 (amd64) and aarch64/arm64 are supported.\n' "${arch}" >&2
      return 1
      ;;
  esac
}

# Print the kubectl client version string reported by
# `kubectl version --client` (e.g. "Client Version: v1.31.0"). Returns
# nothing if kubectl is not installed or its output cannot be parsed.
kubectl_client_version() {
  local line
  line="$(kubectl version --client 2>/dev/null | grep -E 'Client Version' | head -n1 || true)"
  if [[ -z "${line}" ]]; then
    line="$(kubectl version --client 2>/dev/null | head -n1 || true)"
  fi
  printf '%s' "${line}"
}

# Print the helm version string reported by `helm version --short`
# (e.g. "v3.18.2+g04cad46"). Returns nothing if helm is not installed
# or its output cannot be parsed.
helm_client_version() {
  local line
  line="$(helm version --short 2>/dev/null || true)"
  printf '%s' "${line}"
}

# Print a cast-cli version string by trying the invocations the upstream
# CLI exposes in turn: `version`, then `--version`, then the first line of
# `--help`. (The cast.ai installer ships the binary as `castctl`, which
# currently does not implement `--version`; `version` is the reliable probe.)
# Returns nothing if none yields output.
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

# Install kubectl from the official Kubernetes static binary release when it
# is not already present on PATH. Idempotent: if kubectl is found, the
# function reports the existing version and returns without changes.
install_kubectl() {
  local arch tmp version_output

  if command_exists kubectl; then
    version_output="$(kubectl_client_version)"
    if [[ -n "${version_output}" ]]; then
      log "kubectl: found, skipping (${version_output})"
    else
      log "kubectl: found, skipping"
    fi
    return 0
  fi

  log "kubectl: not found, installing latest stable..."

  arch="$(detect_arch)"
  tmp="$(mktemp -d)"
  # Single-quote the trap body so ${tmp} expands when the trap fires.
  trap 'rm -rf "${tmp}"' RETURN

  if ! curl -fL "https://dl.k8s.io/release/$(curl -fL https://dl.k8s.io/release/stable.txt)/bin/linux/${arch}/kubectl" -o "${tmp}/kubectl"; then
    log "error: failed to download kubectl binary from dl.k8s.io" >&2
    return 1
  fi

  if [[ -w /usr/local/bin ]]; then
    install -m 0755 "${tmp}/kubectl" /usr/local/bin/kubectl
  else
    sudo install -m 0755 "${tmp}/kubectl" /usr/local/bin/kubectl
  fi

  version_output="$(kubectl_client_version)"
  if [[ -n "${version_output}" ]]; then
    log "kubectl installed: ${version_output}"
  else
    log "kubectl installed"
  fi
}

# Install helm from the official get-helm-3 installer when it is not
# already present on PATH. Idempotent: if helm is found, the function
# reports the existing version and returns without changes. Defaults
# HELM_INSTALL_DIR to /usr/local/bin (using `sudo -nE` only when that
# directory is not writable by the current user); falls back to the
# user-local bin ($HOME/.local/bin) when a privileged install cannot
# succeed.
install_helm() {
  local tmp version_output install_ok
  local helm_install_dir use_sudo

  if command_exists helm; then
    version_output="$(helm_client_version)"
    if [[ -n "${version_output}" ]]; then
      log "helm: found, skipping (${version_output})"
    else
      log "helm: found, skipping"
    fi
    return 0
  fi

  log "helm: not found, installing latest stable..."

  tmp="$(mktemp -d)"
  # Single-quote the trap body so ${tmp} expands when the trap fires.
  trap 'rm -rf "${tmp}"' RETURN

  if ! curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o "${tmp}/get_helm.sh"; then
    log "error: failed to download get-helm-3 installer from raw.githubusercontent.com" >&2
    return 1
  fi

  helm_install_dir="/usr/local/bin"
  use_sudo=0
  if [[ ! -w "${helm_install_dir}" ]] && command_exists sudo; then
    use_sudo=1
  fi

  # First attempt: install into /usr/local/bin (with sudo -nE if
  # needed). `sudo -n` keeps the run non-interactive; if elevated auth
  # cannot proceed the command fails fast and we fall back below.
  install_ok=0
  mkdir -p "${helm_install_dir}"
  if [[ "${use_sudo}" == "1" ]]; then
    if sudo -nE HELM_INSTALL_DIR="${helm_install_dir}" bash "${tmp}/get_helm.sh"; then
      install_ok=1
    fi
  else
    if HELM_INSTALL_DIR="${helm_install_dir}" bash "${tmp}/get_helm.sh"; then
      install_ok=1
    fi
  fi

  if [[ "${install_ok}" -ne 1 ]]; then
    log "helm: install into ${helm_install_dir} failed; falling back to ${HOME}/.local/bin"
    helm_install_dir="${HOME}/.local/bin"
    mkdir -p "${helm_install_dir}"
    if ! HELM_INSTALL_DIR="${helm_install_dir}" bash "${tmp}/get_helm.sh"; then
      log "error: failed to install helm into ${helm_install_dir}" >&2
      return 1
    fi
  fi

  # Ensure the chosen install dir is reachable for the rest of this
  # script (so the verification step can find helm). Surface a note
  # for the user's shell rc when the dir is not already on PATH.
  case ":${PATH}:" in
    *":${helm_install_dir}:"*) ;;
    *)
      export PATH="${helm_install_dir}:${PATH}"
      log "note: added ${helm_install_dir} to PATH for this session"
      log "note: to use helm in new shells, add 'export PATH=\"${helm_install_dir}:\$PATH\"' to your shell profile"
      ;;
  esac

  version_output="$(helm_client_version)"
  if [[ -n "${version_output}" ]]; then
    log "helm installed: ${version_output}"
  else
    log "helm installed"
  fi
}

# Install the Cast AI CLI (cast-cli) from the official get.cast.ai/linux
# installer when it is not already present on PATH. Idempotent: if
# cast-cli is found, the function reports the existing version and
# returns without changes. If the installer finishes without putting
# cast-cli on PATH, the function falls back to locating the binary under
# the installer-known locations and symlinking it into a writable PATH
# directory (preferring /usr/local/bin via sudo when available, then
# $HOME/.local/bin).
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
    log "error: failed to install cast-cli via get.cast.ai/linux" >&2
    return 1
  fi

  # The cast.ai installer ships the binary as `castctl`. If the user does
  # not already have a `cast-cli` binary/symlink, expose the installed
  # `castctl` as `cast-cli` so the rest of the lesson and this script can
  # use the documented command name.
  if ! command_exists cast-cli && command_exists castctl; then
    castctl_path="$(command -v castctl)"
    castctl_dir="$(dirname "${castctl_path}")"
    if [[ -w "${castctl_dir}" ]]; then
      ln -sf "${castctl_path}" "${castctl_dir}/cast-cli"
    else
      sudo -n ln -sf "${castctl_path}" "${castctl_dir}/cast-cli" 2>/dev/null || true
    fi
  fi

  # The cast.ai installer should put cast-cli (or castctl) on PATH.
  # Re-check before we go searching the filesystem.
  if command_exists cast-cli; then
    version_output="$(cast_cli_version)"
    if [[ -n "${version_output}" ]]; then
      log "cast-cli installed: ${version_output}"
    else
      log "cast-cli installed"
    fi
    return 0
  fi

  # Installer finished without putting cast-cli on PATH. Search a few
  # known install locations and try to expose whichever we find.
  log "cast-cli: not on PATH after installer; searching known locations..."

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
    log "error: cast-cli installer finished but binary not found in known locations" >&2
    return 1
  fi

  # Prefer /usr/local/bin (writable or via sudo); fall back to user-local.
  target_dir="/usr/local/bin"
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
    log "cast-cli: install into ${target_dir} failed; falling back to ${HOME}/.local/bin"
    target_dir="${HOME}/.local/bin"
    mkdir -p "${target_dir}"
    if ! install -m 0755 "${found}" "${target_dir}/cast-cli"; then
      log "error: failed to place cast-cli on PATH (tried /usr/local/bin and ${target_dir})" >&2
      return 1
    fi
  fi

  # Ensure the chosen install dir is reachable for the rest of this
  # script (so the verification step can find cast-cli). Surface a note
  # for the user's shell rc when the dir is not already on PATH.
  case ":${PATH}:" in
    *":${target_dir}:"*) ;;
    *)
      export PATH="${target_dir}:${PATH}"
      log "note: added ${target_dir} to PATH for this session"
      log "note: to use cast-cli in new shells, add 'export PATH=\"${target_dir}:\$PATH\"' to your shell profile"
      ;;
  esac

  version_output="$(cast_cli_version)"
  if [[ -n "${version_output}" ]]; then
    log "cast-cli installed: ${version_output}"
  else
    log "cast-cli installed"
  fi
}

# Configure the `k` shorthand for kubectl in the user's detected shell
# profile. Idempotent: if the alias (or fish equivalent) is already
# present in the chosen profile, the function logs and returns without
# making changes. When the alias is appended, the function also attempts
# to source the profile in the current shell so the alias is available
# immediately; if sourcing fails (e.g. fish config sourced by bash, or
# a non-interactive environment) the function logs a manual fallback
# instruction.
#
# The profile is chosen primarily from $SHELL. If $SHELL is unset or names
# a shell we do not recognise, we fall back to the first existing file out
# of ~/.bashrc, ~/.zshrc, ~/.profile, defaulting to ~/.profile when none
# exist.
setup_alias() {
  local shell_path shell_name profile alias_line

  shell_path="${SHELL:-}"
  shell_name="$(basename "${shell_path}")"

  case "${shell_name}" in
    bash)
      profile="${HOME}/.bashrc"
      alias_line="alias k=kubectl"
      ;;
    zsh)
      profile="${HOME}/.zshrc"
      alias_line="alias k=kubectl"
      ;;
    fish)
      profile="${HOME}/.config/fish/config.fish"
      alias_line="abbr k kubectl"
      ;;
    *)
      # $SHELL is empty or unknown: pick the first existing profile file,
      # or default to ~/.profile if none exist.
      if [[ -f "${HOME}/.bashrc" ]]; then
        profile="${HOME}/.bashrc"
      elif [[ -f "${HOME}/.zshrc" ]]; then
        profile="${HOME}/.zshrc"
      elif [[ -f "${HOME}/.profile" ]]; then
        profile="${HOME}/.profile"
      else
        profile="${HOME}/.profile"
      fi
      alias_line="alias k=kubectl"
      ;;
  esac

  # Skip when the alias is already configured in the chosen profile.
  # Match the canonical `alias k=kubectl`, the single- and double-quoted
  # variants (`alias k='kubectl'`, `alias k="kubectl"`), and the fish
  # `abbr` form (`abbr k kubectl`). The single-quote literal is escaped
  # with the close-quote / escaped-quote / open-quote idiom.
  if [[ -f "${profile}" ]] && \
     grep -Eq '^[[:space:]]*(alias k=kubectl|alias k='"'"'kubectl'"'"'|alias k="kubectl"|abbr k kubectl)[[:space:]]*$' "${profile}"; then
    log "alias k=kubectl already configured, skipping"
    return 0
  fi

  # Append the alias line, creating parent directories as needed.
  mkdir -p "$(dirname "${profile}")"
  printf '\n# Added by validate-setup.sh\n%s\n' "${alias_line}" >> "${profile}"
  log "alias k=kubectl added to ${profile}"

  # Attempt to source the profile in the current shell so the alias is
  # available immediately. The `.` runs inside an `if` condition so a
  # failed source (e.g. fish config sourced by bash, or a non-interactive
  # environment) does not abort the validator under `set -e`.
  # shellcheck disable=SC1090
  if . "${profile}" 2>/dev/null; then
    log "sourced ${profile} in current shell"
  else
    log "note: run '. ${profile}' (or open a new shell) to activate the alias"
  fi
}

main() {
  local overall_status=0

  log "Checking required CLIs..."
  install_kubectl || overall_status=1
  install_helm || overall_status=1
  install_cast_cli || overall_status=1
  setup_alias || overall_status=1

  if [[ "${overall_status}" -eq 0 ]]; then
    log "All checks passed. You are ready for the next lesson."
  else
    log "One or more checks failed. Review the output above and re-run after fixing the issue."
  fi

  return "${overall_status}"
}

main "$@"
