#!/usr/bin/env bash
# web-deny-templates.sh — drop deny-access templates for every common web
# server into a directory of sensitive Shannon reports.
#
# Why every server: this script runs unconditionally after save-report.sh.
# It does not know (and does not need to know) which server fronts the dir
# — having Nginx/Apache/Caddy/Lighttpd/IIS snippets ready costs a few KB
# and lets the user paste-and-reload without us touching /etc/.
#
# Only `.htaccess` activates automatically — and only when the vhost has
# `AllowOverride All|AuthConfig|Limit`. Everything else is a template to
# paste into the active server config. The directory itself is also
# chmod 700 as the real first-line defense; even if the deny rules never
# load, the web server's user typically can't enter a 700-root dir.
#
# Usage: web-deny-templates.sh <dir>

set -uo pipefail

dir="${1:-}"
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  echo "usage: $0 <dir>" >&2
  exit 1
fi

base="$(basename "$dir")"

# ── Apache: .htaccess (auto when AllowOverride permits) ────────────────────
cat > "$dir/.htaccess" <<'APACHE'
# Shannon pentest reports — sensitive findings (DB creds, attack-surface
# intel, secret material). Deny ALL web access.
#
# This file is honored ONLY when the vhost allows .htaccess overrides.
# BT Panel and many LNMP setups use `AllowOverride None` by default — in
# that case this file is INERT. Check with:
#   apachectl -t -D DUMP_INCLUDES | grep AllowOverride
# When overrides are disabled, paste _apache-deny.conf into the vhost.

<IfModule mod_authz_core.c>
  Require all denied
</IfModule>

<IfModule !mod_authz_core.c>
  Order deny,allow
  Deny from all
</IfModule>
APACHE

# ── Apache: vhost-level snippet (for AllowOverride None) ───────────────────
cat > "$dir/_apache-deny.conf" <<APACHE
# Paste inside the matching <VirtualHost ...> block, then:
#   apachectl configtest && apachectl graceful
<Directory "${dir}">
    Require all denied
    # Apache 2.2 fallback:
    # Order deny,allow
    # Deny from all
</Directory>
APACHE

# ── Nginx: location snippet ────────────────────────────────────────────────
cat > "$dir/_nginx-deny.conf" <<NGINX
# Paste inside the matching server { } block, then:
#   nginx -t && nginx -s reload
# The ^~ prefix ensures this match wins over regex location blocks.
location ^~ /${base}/ {
    deny all;
    return 404;          # 404 leaks less than 403
    access_log off;
    log_not_found off;
}
# Kill direct hits without trailing slash too:
location = /${base} { return 404; }
NGINX

# ── Caddy: site-block snippet ──────────────────────────────────────────────
cat > "$dir/_caddy-deny.Caddyfile" <<CADDY
# Paste inside the matching site block, then: caddy reload
@shannon_reports path /${base}/* /${base}
respond @shannon_reports 404
CADDY

# ── Lighttpd: conditional URL deny ─────────────────────────────────────────
cat > "$dir/_lighttpd-deny.conf" <<LIGHTTPD
# Add to lighttpd.conf or an include, then: service lighttpd reload
\$HTTP["url"] =~ "^/${base}(/|\$)" {
    url.access-deny = ( "" )
}
LIGHTTPD

# ── IIS: web.config (rare on Linux but cheap to ship) ──────────────────────
cat > "$dir/_iis-web.config" <<'IIS'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <security>
      <authorization>
        <clear />
        <add accessType="Deny" users="*" />
      </authorization>
    </security>
  </system.webServer>
</configuration>
IIS

# ── README ────────────────────────────────────────────────────────────────
cat > "$dir/README.PROTECT.md" <<README
# Shannon report directory — public-access protection

This directory holds Shannon pentest output: DB credentials, attack-surface
enumeration, secret material recovered during scans. **It must never be
reachable over HTTP.**

If this directory lives outside any docroot (e.g., \`\$HOME/shannon-reports/\`),
the dir-level \`chmod 700\` already prevents the web-server user from
entering it. No further action needed.

If this directory lives inside a docroot, configure your web server to deny
it. Pre-generated templates are bundled here:

| File | Server | Activation |
|---|---|---|
| \`.htaccess\` | Apache | Auto — **only if** the vhost has \`AllowOverride All\` (or \`AuthConfig\`+\`Limit\`). With \`AllowOverride None\` (BT/LNMP default), this file is inert. |
| \`_apache-deny.conf\` | Apache | Manual — paste into the \`<VirtualHost>\`, then \`apachectl graceful\`. |
| \`_nginx-deny.conf\` | Nginx | Manual — paste into the matching \`server { }\`, then \`nginx -t && nginx -s reload\`. |
| \`_caddy-deny.Caddyfile\` | Caddy | Manual — paste into the site block, then \`caddy reload\`. |
| \`_lighttpd-deny.conf\` | Lighttpd | Manual — add to config, then \`service lighttpd reload\`. |
| \`_iis-web.config\` | IIS | Rename to \`web.config\`. Auto. |

**Verify** access is actually blocked before treating the engagement as closed:

\`\`\`
curl -sI https://<your-site>/${base}/ | head -n1
# Expected: 403 or 404.  If 200 — none of the templates activated;
# pick the snippet matching your server, paste it into the vhost,
# reload, and re-test.
\`\`\`
README

# Tighten dir perms — the real first-line defense. Web-server users (www,
# www-data, nginx) typically can't enter a root-owned 700 dir, which makes
# the templates' activation status moot.
chmod 700 "$dir" 2>/dev/null || true

echo "DENY_TEMPLATES_WRITTEN=$dir" >&2
exit 0
