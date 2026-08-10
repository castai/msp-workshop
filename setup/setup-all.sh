#!/usr/bin/env bash
#
# setup-all.sh — One-shot workshop environment setup.
#
# Runs the full MSP workshop setup pipeline:
#   1. install-docker.sh
#   2. validate-setup.sh
#   3. install-kind.sh [--recreate]
#   4. verify-kind.sh
#
# Usage:
#   ./setup-all.sh           idempotent setup
#   ./setup-all.sh --recreate  forward --recreate to install-kind.sh
#   ./setup-all.sh --help      print usage and exit

set -euo pipefail

# ANSI colors for messages.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log() { printf "${GREEN}[setup-all]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[setup-all]${NC} %s\n" "$*" >&2; }
err() { printf "${RED}[setup-all]${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}[setup-all]${NC} %s\n" "$*"; }

print_banner() {
  printf '%b' "${BOLD}${BLUE}"
  printf '============================================================\n'
  printf '  MSP Workshop — Full Environment Setup\n'
  printf '============================================================\n'
  printf '%b' "${NC}"
  printf '\n'
}

print_usage() {
  cat <<'EOF'
Usage: ./setup-all.sh [--recreate]

Options:
  --recreate   forward --recreate to install-kind.sh (delete + recreate cluster)
  -h, --help   print this help and exit

Steps performed in order (stops on first failure):
  1. install-docker.sh
  2. validate-setup.sh
  3. install-kind.sh [--recreate]
  4. verify-kind.sh
EOF
}

# Run a named setup step. Prints [RUN]/[OK]/[FAIL] in color and aborts on failure.
run_step() {
  local name="$1"
  shift

  printf "${BLUE}[RUN]${NC}  %s\n" "${name}"
  if "$@"; then
    printf "${GREEN}[OK]${NC}   %s\n" "${name}"
    return 0
  fi
  printf "${RED}[FAIL]${NC} %s\n" "${name}" >&2
  return 1
}

main() {
  local recreate=0

  for arg in "$@"; do
    case "${arg}" in
      --recreate)
        recreate=1
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      *)
        err "unknown argument: ${arg}"
        printf '\n'
        print_usage
        exit 1
        ;;
    esac
  done

  print_banner

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  run_step "install-docker.sh"        bash "${script_dir}/install-docker.sh"
  run_step "validate-setup.sh"        bash "${script_dir}/validate-setup.sh"

  if [[ "${recreate}" -eq 1 ]]; then
    run_step "install-kind.sh --recreate" bash "${script_dir}/install-kind.sh" --recreate
  else
    run_step "install-kind.sh"        bash "${script_dir}/install-kind.sh"
  fi

  run_step "verify-kind.sh"           bash "${script_dir}/verify-kind.sh"

  printf '\n%b' "${BOLD}${GREEN}"
  printf '============================================================\n'
  printf '  Workshop setup complete!\n'
  printf '  cluster: workshop-cluster\n'
  printf '  context: kind-workshop-cluster\n'
  printf '============================================================\n'
  printf '%b\n' "${NC}"
}

main "$@"
