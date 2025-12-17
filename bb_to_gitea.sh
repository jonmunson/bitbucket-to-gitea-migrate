#!/usr/bin/env bash
set -e

########################################
# PATHS (script-local, safe)
########################################
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="$SCRIPT_DIR/.bb-migrate-state"
REPO_LIST="$SCRIPT_DIR/repos.txt"
DONE_FILE="$WORKDIR/done.txt"
FAIL_FILE="$WORKDIR/fail.txt"

mkdir -p "$WORKDIR"
touch "$DONE_FILE" "$FAIL_FILE"

########################################
# HELPERS
########################################
ts() { date +"%Y-%m-%d %H:%M:%S"; }
now() { date +%s; }

prompt_var() {
  var_name="$1"
  prompt="$2"
  default_val="$3"
  required="$4"
  help="$5"

  if [ -n "$help" ]; then
    printf "%s\n" "$help"
  fi

  while :; do
    if [ -n "$default_val" ]; then
      printf "%s [%s]: " "$prompt" "$default_val"
    else
      printf "%s: " "$prompt"
    fi
    if ! IFS= read -r input; then
      echo
      echo "ERROR: input required for $var_name"
      exit 1
    fi
    if [ -z "$input" ]; then
      input="$default_val"
    fi
    if [ -n "$input" ]; then
      eval "$var_name=\$input"
      export "$var_name"
      return
    fi
    if [ "$required" != "required" ]; then
      eval "$var_name="
      export "$var_name"
      return
    fi
    echo "ERROR: $var_name is required"
  done
}

require_var() {
  var_name="$1"
  prompt="$2"
  help="$3"

  eval "current=\${$var_name}"
  if [ -n "$current" ]; then
    return
  fi
  if [ ! -t 0 ]; then
    echo "ERROR: $var_name is required (set it as an environment variable)"
    exit 1
  fi
  prompt_var "$var_name" "$prompt" "" "required" "$help"
}

set_optional_var() {
  var_name="$1"
  prompt="$2"
  default_val="$3"
  help="$4"

  eval "current=\${$var_name}"
  if [ -n "$current" ]; then
    return
  fi
  if [ ! -t 0 ]; then
    eval "$var_name=\$default_val"
    export "$var_name"
    return
  fi
  prompt_var "$var_name" "$prompt" "$default_val" "optional" "$help"
}

########################################
# REQUIRED ENV VARS (prompt if missing)
########################################
require_var "BB_WORKSPACE" "Bitbucket workspace ID" \
  "Find this in Bitbucket Cloud under Workspace settings (URL slug)."
require_var "GITEA_OWNER" "Gitea owner (user or org name)" \
  "Use your Gitea username or the organization name that will own the repos."
require_var "GITEA_TOKEN" "Gitea access token" \
  "Generate in Gitea under Settings -> Applications -> Generate New Token."

########################################
# OPTIONAL ENV VARS (safe defaults)
########################################
set_optional_var "GITEA_URL" "Gitea base URL" "http://localhost:3000" \
  "The base HTTP URL for the Gitea instance (no trailing slash)."
set_optional_var "GITEA_SSH_HOST" "Gitea SSH host" "localhost" \
  "The SSH host for Git operations (e.g. gitea.example.com)."
set_optional_var "GITEA_SSH_PORT" "Gitea SSH port" "22" \
  "The SSH port for Git operations."
set_optional_var "GITEA_OWNER_TYPE" "Gitea owner type (user or org)" "user" \
  "Use 'user' for a personal account or 'org' for a Gitea organization."
GITEA_URL="${GITEA_URL%/}"

already_done() {
  grep -qx "$1" "$DONE_FILE" 2>/dev/null
}

gitea_repo_exists() {
  code="$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $GITEA_TOKEN" \
    "$GITEA_URL/api/v1/repos/$GITEA_OWNER/$1")"
  [ "$code" = "200" ]
}

create_gitea_repo() {
  if [ "$GITEA_OWNER_TYPE" = "org" ]; then
    url="$GITEA_URL/api/v1/orgs/$GITEA_OWNER/repos"
  else
    url="$GITEA_URL/api/v1/user/repos"
  fi

  curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $GITEA_TOKEN" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "{\"name\":\"$1\",\"private\":true}" \
    "$url"
}

########################################
# VALIDATION
########################################
[ "$GITEA_OWNER_TYPE" = "user" ] || [ "$GITEA_OWNER_TYPE" = "org" ] || {
  echo "ERROR: GITEA_OWNER_TYPE must be 'user' or 'org'"
  exit 1
}

[ -f "$REPO_LIST" ] || {
  echo "ERROR: repos.txt not found next to script:"
  echo "  $REPO_LIST"
  exit 1
}

TOTAL="$(grep -c . "$REPO_LIST" | tr -d ' ')"
[ "$TOTAL" -gt 0 ] || {
  echo "ERROR: repos.txt is empty"
  exit 1
}

########################################
# MIGRATION
########################################
echo "[$(ts)] Migrating $TOTAL repositories"
START_ALL="$(now)"
COUNT=0

while IFS= read -r SLUG; do
  [ -n "$SLUG" ] || continue
  COUNT=$((COUNT + 1))

  if already_done "$SLUG"; then
    echo "[$(ts)] ($COUNT/$TOTAL) SKIP $SLUG"
    continue
  fi

  echo "[$(ts)] ($COUNT/$TOTAL) Migrating $SLUG"
  START_ONE="$(now)"

  # Ensure repo exists in Gitea
  if ! gitea_repo_exists "$SLUG"; then
    code="$(create_gitea_repo "$SLUG")"
    if [ "$code" != "201" ] && [ "$code" != "409" ]; then
      echo "  ERROR creating repo (HTTP $code)"
      echo "$SLUG" >> "$FAIL_FILE"
      continue
    fi
  fi

  # Clone from Bitbucket
  rm -rf "$WORKDIR/$SLUG.git"
  if ! git clone --mirror \
      "git@bitbucket.org:$BB_WORKSPACE/$SLUG.git" \
      "$WORKDIR/$SLUG.git"; then
    echo "  ERROR cloning from Bitbucket"
    echo "$SLUG" >> "$FAIL_FILE"
    continue
  fi

  # Push to Gitea
  cd "$WORKDIR/$SLUG.git"
  git remote set-url --push origin \
    "ssh://git@$GITEA_SSH_HOST:$GITEA_SSH_PORT/$GITEA_OWNER/$SLUG.git"

  if git push --mirror; then
    echo "$SLUG" >> "$DONE_FILE"
    DURATION="$(( $(now) - START_ONE ))"
    echo "  OK (${DURATION}s)"
  else
    echo "  ERROR pushing to Gitea"
    echo "$SLUG" >> "$FAIL_FILE"
  fi

  cd "$SCRIPT_DIR"
done < "$REPO_LIST"

########################################
# DONE
########################################
TOTAL_TIME="$(( $(now) - START_ALL ))"
echo
echo "[$(ts)] COMPLETE in ${TOTAL_TIME}s"
echo "Successful: $DONE_FILE"
echo "Failed:     $FAIL_FILE"
