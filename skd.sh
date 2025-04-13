#!/bin/bash

cat <<'EOF'
      _       _       _     
     | |     | |     | |    
  ___| | ____| |  ___| |__  
 / __| |/ / _` | / __| '_ \ 
 \__ \   < (_| |_\__ \ | | |
 |___/_|\_\__,_(_)___/_| |_|
EOF

echo
# Version 2.3.17

set -e

# Colors
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
CYN='\033[0;36m'
GRY='\033[1;30m'
NC='\033[0m' # No color

# Logging with timestamps (only when DEBUG_MODE=1)
log() {
  local level="$1"
  local color="$2"
  local message="$3"
  [[ "$DEBUG_MODE" == 1 ]] && printf "${color}[%s] [%s] %s${NC}\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$level" "$message"
}

show_help() {
  echo -e "SSH Key Deployment Script - Version 2.3.17"
  echo -e ""
  echo -e "Usage: $0 [FILE] [OPTIONS]"
  echo -e ""
  echo -e "SSH Key deployment automation script"
  echo -e ""
  echo -e "Arguments:"
  echo -e "  FILE                YAML input file. If not provided, interactive mode is used."
  echo -e ""
  echo -e "Options:"
  echo -e "  -d, --debug         Enable debug output with timestamps"
  echo -e "  -s, --syntax        Show expected YAML syntax format"
  echo -e "  -h, --help          Show this help message and exit"
}

show_syntax() {
  echo -e "# YAML SYNTAX EXPECTATION:"
  echo -e "# - name: host-label"
  echo -e "#   user: username"
  echo -e "#   host: ip.or.domain"
  echo -e "#   port: optional (default 22)"
  echo -e "#   key_type: optional (default ed25519)"
  echo -e "#   aliases: [alias1, alias2, ...]"
  echo -e "#   password: optional (use with sshpass)"
}

KEY_DIR="$HOME/.ssh/keys"
CONFIG_FILE="$HOME/.ssh/config"
mkdir -p "$KEY_DIR"
chmod 700 "$HOME/.ssh"

FILE=""
DEBUG_MODE=0
WANT_HELP=0
WANT_SYNTAX=0

# Pre-scan args for -h or -s (highest priority)
for arg in "$@"; do
  case "$arg" in
    -h|--help) WANT_HELP=1 ;;
    -s|--syntax) WANT_SYNTAX=1 ;;
  esac
done

if (( WANT_SYNTAX )); then
  show_syntax
  echo
fi

if (( WANT_HELP )); then
  show_help
  exit 0
fi

# Parse remaining args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--debug)
      DEBUG_MODE=1
      ;;
    -*)
      echo -e "${RED}[!] Unknown option: $1${NC}"
      show_help
      exit 1
      ;;
    *)
      if [[ -z "$FILE" ]]; then
        FILE="$1"
      else
        echo -e "${RED}[!] Unexpected argument: $1${NC}"
        show_help
        exit 1
      fi
      ;;
  esac
  shift
done

SUCCESS_LIST=()
FAILURE_LIST=()

TMP_YQ="/tmp/yq_$$"
trap '[[ -f "$TMP_YQ" ]] && rm -f "$TMP_YQ"' EXIT

# Interactive mode
if [[ -z "$FILE" ]]; then
  echo -e "${CYN}[!] No input file provided. Entering interactive mode.${NC}"
  read -p "Key name: " NAME
  read -p "Username: " USER
  read -p "Host (IP or FQDN): " HOST
  read -p "Port [22]: " PORT
  PORT=${PORT:-22}
  read -p "Key type [ed25519]: " TYPE
  TYPE=${TYPE:-ed25519}

  ALIASES=()
  echo "Enter aliases, if any:"
  echo "- You can enter them comma-separated, space-separated, or one per line."
  echo "- Press Enter on an empty line to finish."
  while true; do
    read -p "Alias: " line
    [[ -z "$line" ]] && break
    IFS=', ' read -ra PARTS <<< "$line"
    for alias in "${PARTS[@]}"; do
      [[ -n "$alias" ]] && ALIASES+=("$alias")
    done
  done

  read -s -p "Password: " PASSWORD
  echo
  log "DEBUG" "$GRY" "Using password: '$PASSWORD'"

  log "INFO" "$CYN" "Validating SSH password..."
  if ! sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p "$PORT" "$USER@$HOST" "exit" 2>/dev/null; then
    echo -e "${RED}[!] Authentication failed. Aborting.${NC}"
    exit 1
  fi

  KEY_PATH="$KEY_DIR/${NAME}_${TYPE}"

  log "INFO" "$CYN" "Generating key for $NAME ($TYPE)..."
  ssh-keygen -t "$TYPE" -f "$KEY_PATH" -N ""

  log "INFO" "$CYN" "Updating SSH config for $NAME..."
  {
    echo "##$NAME"
    echo -n "Host $HOST $NAME"
    for alias in "${ALIASES[@]}"; do
      echo -n " $alias"
    done
    echo
    echo "    Hostname $HOST"
    echo "    User $USER"
    echo "    Port $PORT"
    echo "    IdentityFile $KEY_PATH"
    echo
  } >> "$CONFIG_FILE"

  log "INFO" "$CYN" "Deploying key to $USER@$HOST:$PORT..."
  if sshpass -p "$PASSWORD" scp -P "$PORT" -o StrictHostKeyChecking=no "$KEY_PATH.pub" "$USER@$HOST:/tmp/${NAME}_${TYPE}.pub" && \
     sshpass -p "$PASSWORD" ssh -p "$PORT" -o StrictHostKeyChecking=no "$USER@$HOST" "
       mkdir -p ~/.ssh &&
       chmod 700 ~/.ssh &&
       cat /tmp/${NAME}_${TYPE}.pub >> ~/.ssh/authorized_keys &&
       chmod 600 ~/.ssh/authorized_keys &&
       rm /tmp/${NAME}_${TYPE}.pub
     "; then
    echo -e "${GRN}[*] Key deployed successfully.${NC}"
  else
    echo -e "${RED}[!] Failed to deploy key.${NC}"
    exit 1
  fi

  unset PASSWORD
  echo -e "${CYN}[*] Done.${NC}"
  exit 0
fi

# File input mode — check existence
if [[ ! -f "$FILE" ]]; then
  echo -e "${RED}[!] File not found: $FILE${NC}"
  exit 1
fi

# yq setup
if ! command -v yq >/dev/null 2>&1; then
  echo -e "${YLW}[!] yq not found. Downloading temporary copy...${NC}"

# Temporary sshpass install if missing
TMP_SSHPASS="/tmp/sshpass_$$"

if ! command -v sshpass >/dev/null 2>&1; then
  echo -e "${YLW}[!] sshpass not found. Downloading and compiling temporary copy...${NC}"
  curl -sSL https://ftp.gnu.org/gnu/sshpass/sshpass-1.09.tar.gz -o /tmp/sshpass.tar.gz
  tar -xzf /tmp/sshpass.tar.gz -C /tmp
  cd /tmp/sshpass-1.09
  ./configure --prefix="$TMP_SSHPASS" >/dev/null 2>&1
  make >/dev/null 2>&1
  make install >/dev/null 2>&1
  export PATH="$TMP_SSHPASS/bin:$PATH"
  cd - >/dev/null
fi

  curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o "$TMP_YQ"
  chmod +x "$TMP_YQ"
  YQ="$TMP_YQ"
else
  YQ="$(command -v yq)"
fi

# Validate YAML
if ! "$YQ" e '.' "$FILE" >/dev/null 2>&1; then
  echo -e "${RED}[!] Malformed YAML in $FILE${NC}"
  show_syntax
  exit 1
fi

TOTAL=$("$YQ" e 'length' "$FILE")
echo -e "${CYN}[*] Found $TOTAL host entries${NC}"

for i in $(seq 0 $((TOTAL - 1))); do
  log "DEBUG" "$GRY" "Host $i raw entry:"
  [[ "$DEBUG_MODE" == 1 ]] && "$YQ" e ".[$i]" "$FILE"

  NAME=$("$YQ" e ".[$i].name" "$FILE")
  USER=$("$YQ" e ".[$i].user" "$FILE")
  HOST=$("$YQ" e ".[$i].host" "$FILE")
  PORT=$("$YQ" e ".[$i].port // 22" "$FILE")
  TYPE=$("$YQ" e ".[$i].key_type // \"ed25519\"" "$FILE")
  PASSWORD=$("$YQ" e ".[$i].password" "$FILE" 2>/dev/null)
  PASSWORD=${PASSWORD:-}
  ALIASES_RAW=$("$YQ" e ".[$i].aliases[]" "$FILE" 2>/dev/null || echo "")

  log "DEBUG" "$GRY" "Using password: '$PASSWORD'"

  KEY_PATH="$KEY_DIR/${NAME}_${TYPE}"

  log "INFO" "$CYN" "Generating key for $NAME ($TYPE)..."
  ssh-keygen -t "$TYPE" -f "$KEY_PATH" -N ""

  ALIAS_LINE="$HOST $NAME"
  for alias in $ALIASES_RAW; do
    ALIAS_LINE+=" $alias"
  done

  log "INFO" "$CYN" "Updating SSH config for $NAME..."
  {
    echo "##$NAME"
    echo "Host $ALIAS_LINE"
    echo "    Hostname $HOST"
    echo "    User $USER"
    echo "    Port $PORT"
    echo "    IdentityFile $KEY_PATH"
    echo
  } >> "$CONFIG_FILE"

  log "INFO" "$CYN" "Deploying key to $USER@$HOST:$PORT..."
  if [[ -n "$PASSWORD" && "$PASSWORD" != "[SUCCESS]" && "$PASSWORD" != "[FAILURE]" ]]; then
    if sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p "$PORT" "$USER@$HOST" "exit" 2>/dev/null; then
      echo -e "${GRN}[+] Password authentication succeeded${NC}"
      if sshpass -p "$PASSWORD" scp -P "$PORT" -o StrictHostKeyChecking=no "$KEY_PATH.pub" "$USER@$HOST:/tmp/${NAME}_${TYPE}.pub" && \
         sshpass -p "$PASSWORD" ssh -p "$PORT" -o StrictHostKeyChecking=no "$USER@$HOST" "
           mkdir -p ~/.ssh &&
           chmod 700 ~/.ssh &&
           cat /tmp/${NAME}_${TYPE}.pub >> ~/.ssh/authorized_keys &&
           chmod 600 ~/.ssh/authorized_keys &&
           rm /tmp/${NAME}_${TYPE}.pub
         "; then
        "$YQ" e ".[$i].password = \"[SUCCESS]\"" -i "$FILE"
        SUCCESS_LIST+=("$NAME -> SUCCESS")
      else
        echo -e "${RED}[!] Deployment failed after authentication succeeded.${NC}"
        "$YQ" e ".[$i].password = \"[FAILURE]\"" -i "$FILE"
        FAILURE_LIST+=("$NAME -> FAILURE")
        continue
      fi
    else
      echo -e "${RED}[!] Authentication failed for $USER@$HOST using password from YAML.${NC}"
      "$YQ" e ".[$i].password = \"[FAILURE]\"" -i "$FILE"
      FAILURE_LIST+=("$NAME -> FAILURE")
      continue
    fi
  else
    if scp -P "$PORT" -o BatchMode=no -o ConnectTimeout=10 "$KEY_PATH.pub" "$USER@$HOST:/tmp/${NAME}_${TYPE}.pub" && \
       ssh -p "$PORT" -o BatchMode=no -o ConnectTimeout=10 "$USER@$HOST" "
         mkdir -p ~/.ssh &&
         chmod 700 ~/.ssh &&
         cat /tmp/${NAME}_${TYPE}.pub >> ~/.ssh/authorized_keys &&
         chmod 600 ~/.ssh/authorized_keys &&
         rm /tmp/${NAME}_${TYPE}.pub
       "; then
      SUCCESS_LIST+=("$NAME -> SUCCESS")
    else
      FAILURE_LIST+=("$NAME -> FAILURE")
    fi
  fi

  unset PASSWORD
done

# Summary
printf "\n===== Deployment Summary =====\n"
for item in "${SUCCESS_LIST[@]}"; do
  printf "${GRN}[OK]   %s${NC}\n" "$item"
done
for item in "${FAILURE_LIST[@]}"; do
  printf "${RED}[FAIL] %s${NC}\n" "$item"
done

if (( ${#FAILURE_LIST[@]} > 0 )); then
  echo -e "${RED}[*] Some keys failed to deploy.${NC}"
else
  echo -e "${GRN}[*] All keys generated and deployed successfully.${NC}"
fi

exit 0
