#!/usr/bin/env bash
#
# manage-ds.sh
# Written by Mark Nienaber – Ping Identity 2025
# Script to manage Ping DS instances with enhanced, user-friendly output:
#   • start, stop, restart, status, help
#   • coloured ticks/crosses, timestamps, aligned columns
#   • each instance has a description

# === Configuration ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/platformconfig.env" ]]; then
    source "${SCRIPT_DIR}/platformconfig.env"
elif [[ -f "${SCRIPT_DIR}/../platformconfig.env" ]]; then
    source "${SCRIPT_DIR}/../platformconfig.env"
fi

DS_BASE="${DS_DIR:-${BASE_INSTALL_DIR:-/ping}/ds}"
declare -A INST_DESC=(
  ["opendj"]="Consolidated DS (All Profiles)"
  ["idrepo"]="AM/IDM Identity Store"
  ["cts"]="AM CTS Store"
  ["config"]="Config Store"
)
ALL_INSTANCES=("${!INST_DESC[@]}")

# Helper to find instance directory
get_instance_dir() {
  local inst="$1"
  if [[ "$inst" == "opendj" ]]; then
    if [[ -d "$DS_BASE/opendj" ]]; then
      echo "$DS_BASE/opendj"
    elif [[ -d "$DS_BASE/opendj/opendj" ]]; then
      echo "$DS_BASE/opendj/opendj"
    else
      echo "$DS_BASE/opendj"
    fi
  else
    if [[ -d "$DS_BASE/$inst/opendj" ]]; then
      echo "$DS_BASE/$inst/opendj"
    elif [[ -d "$DS_BASE/$inst" ]]; then
      echo "$DS_BASE/$inst"
    else
      echo "$DS_BASE/$inst/opendj"
    fi
  fi
}

# === Colours ===
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'  # no colour

# === Logging helper ===
log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# === Help/Usage ===
print_help() {
  cat << EOF

Usage: $0 <command>

Commands:
  ${GREEN}start${NC}    Start all DS instances
  ${YELLOW}stop${NC}    Stop all DS instances
  ${BLUE}restart${NC}  Restart all DS instances
  ${GREEN}status${NC}   Show detailed status for each instance
  ${YELLOW}help${NC}    Display this help message

EOF
}

# === Status reporting ===
status_instances() {
  log "Directory Server Status:"
  echo
  for inst in "${ALL_INSTANCES[@]}"; do
    local desc="${INST_DESC[$inst]}"
    local inst_dir
    inst_dir=$(get_instance_dir "$inst")
    if [[ ! -d "$inst_dir" ]]; then
      continue
    fi
    local pids
    pids=$(ps -ef | grep "[j]ava.*${inst_dir}/config" | awk '{print $2}')
    if [[ -n "$pids" ]]; then
      printf "%-25s ${GREEN}running${NC} [%s(%s)]\n" "$desc" "$inst" "$pids"
    else
      printf "%-25s ${RED}not running${NC}\n" "$desc"
    fi
  done
  echo
}

# === Start/Stop logic with nice output ===
control_instances() {
  local action="$1" color symbol text
  if [[ "$action" == "start" ]]; then
    color="$GREEN"; symbol="✔"; text="started"
  else
    color="$YELLOW"; symbol="■"; text="stopped"
  fi

  log "${action^}ing all DS instances..."
  echo

  for inst in "${ALL_INSTANCES[@]}"; do
    local desc="${INST_DESC[$inst]}"
    local inst_dir
    inst_dir=$(get_instance_dir "$inst")
    if [[ ! -d "$inst_dir" ]]; then
      continue
    fi
    local script="$inst_dir/bin/${action}-ds"
    if [[ -x "$script" ]]; then
      if (cd "$(dirname "$script")" && ./$(basename "$script") &>/dev/null); then
        printf "  %b%s%b  %-25s (%s)\n" "$color" "$symbol" "$NC" "$desc" "$text"
      else
        printf "  ${RED}✖${NC}  %-25s (%s failed)\n" "$desc" "$text"
      fi
    else
      printf "  ${RED}✖${NC}  %-25s (script missing)\n" "$desc"
    fi
  done

  echo
}

start_instances()  { control_instances start; }
stop_instances()   { control_instances stop; }
restart_instances() {
  log "Initiating full restart..."
  echo
  stop_instances
  start_instances
}

# === Main entrypoint ===
if [[ $# -lt 1 ]]; then
  echo "Error: Missing command."
  print_help
  exit 1
fi

case "$1" in
  help|-h|--help) print_help ;;
  status)         status_instances ;;
  start)          start_instances ;;
  stop)           stop_instances ;;
  restart)        restart_instances ;;
  *)
    echo "Error: Unknown command '$1'."
    print_help
    exit 1
    ;;
esac

exit 0
