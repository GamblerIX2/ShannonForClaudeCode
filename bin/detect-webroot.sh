#!/usr/bin/env bash
# detect-webroot.sh — figure out whether the given directory is a live web
# docroot. Output is structured key=value lines the agent parses to decide
# whether to ask the user about report-save location.
#
# Output keys (always all three, even when no):
#   WEBROOT_DETECTED=yes|no
#   WEBROOT_REASON=<one-line reason if yes; empty when no>
#   WEBSERVER=nginx|apache|caddy|lighttpd|unknown   (only meaningful when yes)
#
# Detection layers — any one ⇒ yes:
#   1. Path-prefix match against common webroot locations on Linux distros
#      and panels (BT Panel, LNMP one-click, Debian, Ubuntu, cPanel/Plesk).
#   2. Vhost-config grep — search known web-server config locations for any
#      file mentioning the target path as a fixed string. Loose, but the
#      agent confirms with the user before acting, so false positives just
#      mean an extra question.
#
# Usage: detect-webroot.sh [dir]    (defaults to PWD)

set -uo pipefail

target="${1:-$PWD}"
target_resolved="$(cd "$target" 2>/dev/null && pwd || echo "$target")"

REASON=""
SERVER="unknown"

# Layer 1 — path-prefix.
case "$target_resolved" in
  /www/wwwroot/*)          REASON="cwd inside /www/wwwroot/ (BT Panel webroot layout)"; SERVER="nginx" ;;
  /var/www/*)              REASON="cwd inside /var/www/ (Debian/Ubuntu default)"; SERVER="apache" ;;
  /usr/share/nginx/*)      REASON="cwd inside /usr/share/nginx/ (Nginx default docroot)"; SERVER="nginx" ;;
  /srv/www/*)              REASON="cwd inside /srv/www/" ;;
  /home/*/public_html/*)   REASON="cwd inside ~/public_html (cPanel/Plesk layout)"; SERVER="apache" ;;
  /home/wwwroot/*)         REASON="cwd inside /home/wwwroot/ (LNMP one-click layout)"; SERVER="nginx" ;;
esac

# Layer 2 — search vhost configs for any reference to the target path.
# We grep -F (fixed string) for the path; the agent asks the user to
# confirm, so over-detection is fine, under-detection isn't.
vhost_locations=(
  /etc/nginx/conf.d
  /etc/nginx/sites-enabled
  /etc/nginx/sites-available
  /etc/nginx/vhost.d
  /usr/local/nginx/conf/vhost
  /www/server/panel/vhost/nginx
  /etc/apache2/sites-enabled
  /etc/apache2/sites-available
  /etc/apache2/conf-enabled
  /etc/httpd/conf.d
  /etc/httpd/conf/extra
  /www/server/panel/vhost/apache
  /etc/caddy
  /etc/caddy/sites-enabled
  /etc/caddy/Caddyfile.d
  /etc/lighttpd/conf-enabled
  /etc/lighttpd/vhosts.d
)

hit=""
hit_dir=""
for d in "${vhost_locations[@]}"; do
  [ -d "$d" ] || continue
  hit="$(grep -RlF -- "$target_resolved" "$d" 2>/dev/null | head -n1)"
  if [ -n "$hit" ]; then
    hit_dir="$d"
    break
  fi
done

if [ -n "$hit" ]; then
  case "$hit_dir" in
    *nginx*)      [ "$SERVER" = "unknown" ] && SERVER="nginx" ;;
    *apache*|*httpd*) [ "$SERVER" = "unknown" ] && SERVER="apache" ;;
    *caddy*)      [ "$SERVER" = "unknown" ] && SERVER="caddy" ;;
    *lighttpd*)   [ "$SERVER" = "unknown" ] && SERVER="lighttpd" ;;
  esac
  [ -z "$REASON" ] && REASON="cwd referenced in vhost config: $hit"
fi

if [ -n "$REASON" ]; then
  echo "WEBROOT_DETECTED=yes"
  echo "WEBROOT_REASON=$REASON"
  echo "WEBSERVER=$SERVER"
else
  echo "WEBROOT_DETECTED=no"
  echo "WEBROOT_REASON="
  echo "WEBSERVER="
fi
exit 0
