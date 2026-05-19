#!/usr/bin/env bash
# with-shannon-user.sh — run a command as a non-root user.
#
# Behaviour
#   * If the current process is NOT root (EUID != 0): exec <cmd...> directly.
#   * If the current process IS root: ensure a service user exists (default
#     name: "shannon"), add it to the docker group, grant it ownership of
#     <shannon-dir>, grant it read access to <repo-path> (if given), then
#     re-exec <cmd...> as that user via runuser/su/sudo.
#
# Usage
#   with-shannon-user.sh <shannon-dir> <repo-path-or-empty> -- <cmd> [args...]
#
# Env overrides
#   SHANNON_USER   service username to create/use (default: shannon)
#
# Exit codes
#   non-zero on missing tools, failed user provisioning, or downstream cmd failure.

set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <shannon-dir> <repo-path-or-empty> -- <cmd> [args...]" >&2
  exit 2
fi

SHANNON_DIR="$1"; shift
REPO_PATH="$1"; shift

if [ "${1:-}" != "--" ]; then
  echo "ERROR: expected '--' before command, got '${1:-}'." >&2
  exit 2
fi
shift  # consume the --

if [ "$#" -lt 1 ]; then
  echo "ERROR: no command supplied after '--'." >&2
  exit 2
fi

# Non-root path: just run.
if [ "$(id -u)" -ne 0 ]; then
  exec "$@"
fi

SVC_USER="${SHANNON_USER:-shannon}"

log() { printf '[with-shannon-user] %s\n' "$*" >&2; }

# --- Pick a re-exec mechanism --------------------------------------------------
pick_runas() {
  if command -v runuser >/dev/null 2>&1; then
    echo "runuser"
  elif command -v sudo >/dev/null 2>&1; then
    echo "sudo"
  elif command -v su >/dev/null 2>&1; then
    echo "su"
  else
    echo ""
  fi
}

RUNAS="$(pick_runas)"
if [ -z "$RUNAS" ]; then
  echo "ERROR: need one of runuser, sudo, or su to drop privileges. None found." >&2
  exit 1
fi

# Helper: test whether <user> can read+enter <path>.
runuser_can_read() {
  local u="$1" p="$2"
  case "$RUNAS" in
    runuser) runuser -u "$u" -- test -r "$p" -a -x "$p" ;;
    sudo)    sudo -u "$u" test -r "$p" -a -x "$p" ;;
    su)      su - "$u" -c "test -r '$p' -a -x '$p'" ;;
  esac
}

# --- Ensure service user exists -----------------------------------------------
if ! id -u "$SVC_USER" >/dev/null 2>&1; then
  log "creating service user '$SVC_USER'"
  if command -v useradd >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$SVC_USER"
  elif command -v adduser >/dev/null 2>&1; then
    # busybox/alpine style
    adduser -D -s /bin/sh "$SVC_USER"
  else
    echo "ERROR: neither useradd nor adduser is available; cannot create '$SVC_USER'." >&2
    exit 1
  fi
else
  log "service user '$SVC_USER' already exists"
fi

# --- Ensure service user is in the docker group (for Docker access) -----------
if getent group docker >/dev/null 2>&1; then
  if ! id -nG "$SVC_USER" | tr ' ' '\n' | grep -qx docker; then
    log "adding '$SVC_USER' to docker group"
    if command -v usermod >/dev/null 2>&1; then
      usermod -aG docker "$SVC_USER" || log "warn: usermod -aG docker failed"
    elif command -v adduser >/dev/null 2>&1; then
      adduser "$SVC_USER" docker >/dev/null 2>&1 || log "warn: adduser to docker group failed"
    fi
  fi
else
  log "warn: 'docker' group not found; Shannon may fail to talk to Docker"
fi

# --- Ensure shannon directory exists and is owned by the service user ---------
# If the dir is missing, pre-create it as an empty directory and hand ownership
# to the service user. ensure-shannon.sh treats an existing empty dir as a
# valid clone target (git clone supports cloning into an empty existing dir).
if [ -n "$SHANNON_DIR" ]; then
  if [ ! -e "$SHANNON_DIR" ]; then
    log "creating empty $SHANNON_DIR for service user"
    mkdir -p "$SHANNON_DIR"
  fi
  if [ -d "$SHANNON_DIR" ]; then
    log "chown -R $SVC_USER:$SVC_USER $SHANNON_DIR"
    chown -R "$SVC_USER:$SVC_USER" "$SHANNON_DIR"
  fi
fi

# --- Grant read access to repo path (non-destructive where possible) ---------
if [ -n "$REPO_PATH" ] && [ -d "$REPO_PATH" ]; then
  # Quick check: can the service user already read it?
  if ! runuser_can_read "$SVC_USER" "$REPO_PATH" 2>/dev/null; then
    if command -v setfacl >/dev/null 2>&1; then
      log "granting read ACL on $REPO_PATH for '$SVC_USER'"
      if ! setfacl -R -m "u:${SVC_USER}:rX" "$REPO_PATH" 2>/dev/null; then
        log "warn: setfacl failed (filesystem may not support ACLs); falling back to chmod a+rX"
        chmod -R a+rX "$REPO_PATH" || log "warn: chmod fallback failed; Shannon may not be able to read repo"
      fi
    else
      log "setfacl not available; applying chmod a+rX on $REPO_PATH (non-recursive on files only adds read)"
      chmod -R a+rX "$REPO_PATH" || log "warn: chmod failed; Shannon may not be able to read repo"
    fi
  fi
fi

# --- Re-exec the command as the service user ----------------------------------
log "exec as '$SVC_USER' via $RUNAS: $*"

# Pass HOME so tools that look at it (e.g. pnpm, npm, git) point at the user's home.
SVC_HOME="$(getent passwd "$SVC_USER" | cut -d: -f6)"
SVC_HOME="${SVC_HOME:-/home/$SVC_USER}"

case "$RUNAS" in
  runuser)
    # runuser preserves env when --preserve-environment; we set HOME explicitly.
    exec runuser -u "$SVC_USER" -- env HOME="$SVC_HOME" PATH="$PATH" "$@"
    ;;
  sudo)
    exec sudo -u "$SVC_USER" -H -- env HOME="$SVC_HOME" PATH="$PATH" "$@"
    ;;
  su)
    # su needs a single shell string; quote-escape arguments.
    quoted=""
    for a in "$@"; do
      quoted+=" $(printf '%q' "$a")"
    done
    exec su - "$SVC_USER" -c "env HOME=$(printf '%q' "$SVC_HOME") PATH=$(printf '%q' "$PATH")$quoted"
    ;;
esac
