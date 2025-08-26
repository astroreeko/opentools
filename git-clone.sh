#!/usr/bin/env bash
# git-clone.sh
# Clone (or pull) a GitHub repo via HTTPS using a PAT, fully non-interactive.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  git-clone.sh -r <repo_url> -d <dest_dir> \
    [-t <token> | -T <token_file>] [-u <username>] [--branch <name>] [--shallow] [--basic-url] [-q]

Options:
  -r, --repo URL         GitHub HTTPS URL (e.g., https://github.com/astroreeko/sendmail.git)
  -d, --dest DIR         Destination dir (e.g., /opt/sendmail)
  -t, --token TOKEN      Personal Access Token (PAT)
  -T, --token-file FILE  File with token (either raw token or GITHUB_TOKEN=...)
  -u, --username NAME    Username for auth (default: x-access-token, only used with --basic-url)
  -b, --branch NAME      Branch to clone/pull (default: repo default)
      --shallow          Shallow clone (depth=1)
      --basic-url        Use https://USERNAME:TOKEN@... (⚠️ token appears in process/URL)
  -q, --quiet            Quiet git output
  -h, --help             Show help

Notes:
- Non-interactive by default (GIT_TERMINAL_PROMPT=0). If a token is missing/invalid, it will fail rather than prompt.
- Header mode (default) sends "Authorization: Bearer <token>".
- --basic-url is convenient but less safe: token is visible in command history/ps and may end up in .git/config if you push that URL.
USAGE
}


# # Header mode (recommended). Username not needed here.
# ./git-clone.sh \
#   -r https://github.com/astroreeko/sendmail.git \
#   -d /opt/sendmail \
#   -t 'ghp_XXXXXXXXXXXXXXXXXXXX' \
#   --shallow

# # If you specifically want to pass a username and use Basic auth in the URL:
# ./git-clone.sh \
#   -r https://github.com/astroreeko/sendmail.git \
#   -d /opt/sendmail \
#   -t 'ghp_XXXXXXXXXXXXXXXXXXXX' \
#   -u x-access-token \
#   --basic-url


REPO=""; DEST=""
TOKEN="${GITHUB_TOKEN:-}"
TOKEN_FILE=""
USERNAME="x-access-token"
BRANCH=""
SHALLOW=0
QUIET=0
BASIC_URL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--repo) REPO="$2"; shift 2 ;;
    -d|--dest) DEST="$2"; shift 2 ;;
    -t|--token) TOKEN="$2"; shift 2 ;;
    -T|--token-file) TOKEN_FILE="$2"; shift 2 ;;
    -u|--username) USERNAME="$2"; shift 2 ;;
    -b|--branch) BRANCH="$2"; shift 2 ;;
    --shallow) SHALLOW=1; shift ;;
    --basic-url) BASIC_URL=1; shift ;;
    -q|--quiet) QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

command -v git >/dev/null || { echo "git is required." >&2; exit 1; }

if [[ -z "$REPO" ]]; then read -rp "GitHub repo HTTPS URL: " REPO; fi
if [[ -z "$DEST" ]]; then read -rp "Destination directory: " DEST; fi

# Load token from file if provided
if [[ -n "$TOKEN_FILE" ]]; then
  if grep -q '=' "$TOKEN_FILE" 2>/dev/null; then
    set -a; # export assignments in file
    # shellcheck disable=SC1090
    source "$TOKEN_FILE"
    set +a
    TOKEN="${TOKEN:-${GITHUB_TOKEN:-${TOKEN:-}}}"
  else
    TOKEN="$(head -n1 "$TOKEN_FILE" | tr -d '[:space:]')"
  fi
fi

# Non-interactive: never prompt
export GIT_TERMINAL_PROMPT=0

# Build common git args
GIT_ARGS=()
[[ $QUIET -eq 1 ]] && GIT_ARGS+=(-q)
# Disable helpers that might trigger prompts or cached creds
GIT_ARGS+=(-c credential.helper= -c core.askPass=)

mkdir -p "$(dirname "$DEST")"

if [[ -d "$DEST/.git" ]]; then
  echo "Repo exists at $DEST; pulling…"
  if [[ $BASIC_URL -eq 1 ]]; then
    # Basic URL mode (⚠️ token in process/URL)
    git "${GIT_ARGS[@]}" -C "$DEST" pull --ff-only "https://${USERNAME}:${TOKEN}@${REPO#https://}"
  else
    # Header mode (recommended)
    git "${GIT_ARGS[@]}" -c "http.extraHeader=Authorization: Bearer ${TOKEN}" \
        -C "$DEST" pull --ff-only
  fi
else
  echo "Cloning $REPO -> $DEST"
  CLONE_ARGS=("${GIT_ARGS[@]}")
  [[ -n "$BRANCH" ]] && CLONE_ARGS+=(--branch "$BRANCH")
  [[ $SHALLOW -eq 1 ]] && CLONE_ARGS+=(--depth 1)

  if [[ $BASIC_URL -eq 1 ]]; then
    # Basic URL mode (⚠️ token in process/URL)
    AUTH_URL="https://${USERNAME}:${TOKEN}@${REPO#https://}"
    git "${CLONE_ARGS[@]}" clone "$AUTH_URL" "$DEST"
  else
    # Header mode (recommended)
    git "${CLONE_ARGS[@]}" -c "http.extraHeader=Authorization: Bearer ${TOKEN}" \
        clone "$REPO" "$DEST"
  fi
fi

echo "✅ Done."

