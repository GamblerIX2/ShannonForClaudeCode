#!/usr/bin/env bash
# preflight.sh — verify host has everything Shannon needs.
# Prints a checklist; exits 0 if all green, 1 if any missing.

set -u

GREEN="\033[32m"; RED="\033[31m"; YELLOW="\033[33m"; RESET="\033[0m"
ok()   { printf "  ${GREEN}\xE2\x9C\x94${RESET} %s\n" "$1"; }
fail() { printf "  ${RED}\xE2\x9C\x98${RESET} %s\n" "$1"; FAILED=1; }
warn() { printf "  ${YELLOW}\xE2\x9A\xA0${RESET}  %s\n" "$1"; }

FAILED=0

echo "Shannon preflight"
echo "================="

# Platform
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
  ok "platform: WSL2 (Linux inside Windows)"
  IS_WSL=1
else
  if [ "$(uname -s)" = "Linux" ]; then
    ok "platform: Linux"
    IS_WSL=0
  else
    fail "platform: unsupported ($(uname -s)). Shannon plugin supports Linux and Windows-via-WSL2 only."
    IS_WSL=0
  fi
fi

# git
if command -v git >/dev/null 2>&1; then
  ok "git: $(git --version | awk '{print $3}')"
else
  fail "git: not found. Install with: apt install git  (or your distro equivalent)"
fi

# Node 18+
if command -v node >/dev/null 2>&1; then
  NODE_VER="$(node -v | sed 's/^v//')"
  NODE_MAJOR="${NODE_VER%%.*}"
  if [ "$NODE_MAJOR" -ge 18 ] 2>/dev/null; then
    ok "node: v$NODE_VER"
  else
    fail "node: v$NODE_VER is too old (need 18+). Install via https://nodejs.org or nvm."
  fi
else
  fail "node: not found. Install Node 18+ via https://nodejs.org or nvm."
fi

# pnpm
if command -v pnpm >/dev/null 2>&1; then
  ok "pnpm: $(pnpm --version)"
else
  fail "pnpm: not found. Install with: npm install -g pnpm   (or https://pnpm.io/installation)"
fi

# Docker binary
if command -v docker >/dev/null 2>&1; then
  ok "docker: $(docker --version | sed 's/,$//')"
  # Docker daemon
  if docker info >/dev/null 2>&1; then
    ok "docker daemon: reachable"
  else
    if [ "${IS_WSL:-0}" = "1" ]; then
      fail "docker daemon: not reachable. Install Docker INSIDE WSL2 (not Docker Desktop for Windows): see https://docs.docker.com/engine/install/  Then: sudo service docker start"
    else
      fail "docker daemon: not reachable. Try: sudo systemctl start docker"
    fi
  fi
else
  if [ "${IS_WSL:-0}" = "1" ]; then
    fail "docker: not found. Install Docker INSIDE WSL2 (not Docker Desktop for Windows): https://docs.docker.com/engine/install/"
  else
    fail "docker: not found. Install: curl -fsSL https://get.docker.com | sh"
  fi
fi

echo
if [ "$FAILED" -eq 0 ]; then
  printf "${GREEN}preflight OK${RESET}\n"
  exit 0
else
  printf "${RED}preflight FAILED${RESET} — fix the items above and re-run.\n"
  exit 1
fi
