#!/usr/bin/env bash
set -e

########################################
# REQUIRED ENV VARS
########################################
BB_WORKSPACE="${BB_WORKSPACE:?Set BB_WORKSPACE}"
GITEA_OWNER="${GITEA_OWNER:?Set GITEA_OWNER}"
GITEA_TOKEN="${GITEA_TOKEN:?Set GITEA_TOKEN}"

########################################
# OPTIONAL ENV VARS (safe defaults)
########################################
GITEA_URL="${GITEA_URL:-http://localhost:3000}"
GITEA_SSH_HOST="${GITEA_SSH_HOST:-localhost}"
GITEA_SSH_PORT="${GITEA_SSH_PORT:-22}"
GITEA_OWNER_TYPE="${GITEA_OWNER_TYPE:-user}"   # allowed: user|org
GITEA_URL="${GITEA_URL%/}"

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

