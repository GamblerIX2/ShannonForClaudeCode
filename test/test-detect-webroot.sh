#!/usr/bin/env bash
# Tests for bin/detect-webroot.sh

set -uo pipefail
. "$(dirname "$0")/lib.sh"

echo "test-detect-webroot.sh"

# ── path-prefix detection ────────────────────────────────────────────────
it "BT Panel path → yes + nginx"
run bin/detect-webroot.sh "/www/wwwroot/example.com"
assert_contains "$OUT" "WEBROOT_DETECTED=yes"
it "BT Panel path → reason mentions BT layout"
run bin/detect-webroot.sh "/www/wwwroot/example.com"
assert_contains "$OUT" "BT Panel"
it "BT Panel path → WEBSERVER=nginx"
run bin/detect-webroot.sh "/www/wwwroot/example.com"
assert_contains "$OUT" "WEBSERVER=nginx"

it "Debian /var/www path → apache"
run bin/detect-webroot.sh "/var/www/html"
assert_contains "$OUT" "WEBSERVER=apache"

it "Nginx default /usr/share/nginx → nginx"
run bin/detect-webroot.sh "/usr/share/nginx/html"
assert_contains "$OUT" "WEBSERVER=nginx"

it "cPanel /home/foo/public_html → apache"
run bin/detect-webroot.sh "/home/jdoe/public_html/site"
assert_contains "$OUT" "WEBSERVER=apache"

it "LNMP /home/wwwroot → nginx"
run bin/detect-webroot.sh "/home/wwwroot/site"
assert_contains "$OUT" "WEBSERVER=nginx"

it "/srv/www → yes (unknown server)"
run bin/detect-webroot.sh "/srv/www/foo"
assert_contains "$OUT" "WEBROOT_DETECTED=yes"

# ── non-match cases ──────────────────────────────────────────────────────
it "/root → no"
run bin/detect-webroot.sh "/root"
assert_contains "$OUT" "WEBROOT_DETECTED=no"

it "scratch tmp dir → no (path doesn't match prefix and isn't in vhost)"
run bin/detect-webroot.sh "$SCRATCH"
assert_contains "$OUT" "WEBROOT_DETECTED=no"

# ── output schema invariants ─────────────────────────────────────────────
it "output always has all three keys (yes case)"
run bin/detect-webroot.sh "/www/wwwroot/foo"
keys="$(printf '%s\n' "$OUT" | grep -oE '^(WEBROOT_DETECTED|WEBROOT_REASON|WEBSERVER)=' | sort -u | tr '\n' ',')"
assert_eq "WEBROOT_DETECTED=,WEBROOT_REASON=,WEBSERVER=," "$keys"

it "output always has all three keys (no case)"
run bin/detect-webroot.sh "/root"
keys="$(printf '%s\n' "$OUT" | grep -oE '^(WEBROOT_DETECTED|WEBROOT_REASON|WEBSERVER)=' | sort -u | tr '\n' ',')"
assert_eq "WEBROOT_DETECTED=,WEBROOT_REASON=,WEBSERVER=," "$keys"

it "exits 0 even when no match"
run bin/detect-webroot.sh "/root"
assert_exit_code "0" "$RC"

it "exits 0 on yes match"
run bin/detect-webroot.sh "/www/wwwroot/foo"
assert_exit_code "0" "$RC"

# ── relative path / no-arg behavior ──────────────────────────────────────
it "defaults to PWD when no arg given"
# cwd of this process inherited from test; run with no arg
prev_pwd="$PWD"; cd /root
run bin/detect-webroot.sh
cd "$prev_pwd"
assert_contains "$OUT" "WEBROOT_DETECTED=no"

# ── layer 2: vhost-config grep (via SHANNON_DETECT_VHOST_DIRS) ───────────
it "layer 2 detects when path appears in fake nginx vhost"
fake_nginx="$SCRATCH/nginx-conf.d"
mkdir -p "$fake_nginx"
printf 'server { root /home/randomly-named-site-12345/htdocs; }\n' > "$fake_nginx/site.conf"
run_env "SHANNON_DETECT_VHOST_DIRS=$fake_nginx" bin/detect-webroot.sh "/home/randomly-named-site-12345/htdocs"
assert_contains "$OUT" "WEBROOT_DETECTED=yes"

it "layer 2 sets WEBSERVER=nginx when hit dir contains 'nginx'"
fake_nginx="$SCRATCH/nginx-vhosts"
mkdir -p "$fake_nginx"
printf 'root /home/randomly-named-site-67890/web;\n' > "$fake_nginx/x.conf"
run_env "SHANNON_DETECT_VHOST_DIRS=$fake_nginx" bin/detect-webroot.sh "/home/randomly-named-site-67890/web"
assert_contains "$OUT" "WEBSERVER=nginx"

it "layer 2 sets WEBSERVER=apache when hit dir contains 'apache'"
fake_apache="$SCRATCH/apache-vhosts"
mkdir -p "$fake_apache"
printf 'DocumentRoot /home/randomly-named-site-11111/public\n' > "$fake_apache/site.conf"
run_env "SHANNON_DETECT_VHOST_DIRS=$fake_apache" bin/detect-webroot.sh "/home/randomly-named-site-11111/public"
assert_contains "$OUT" "WEBSERVER=apache"

it "layer 2 misses when path not present"
fake="$SCRATCH/whatever-vhosts"
mkdir -p "$fake"
printf 'server { root /other/path; }\n' > "$fake/x.conf"
run_env "SHANNON_DETECT_VHOST_DIRS=$fake" bin/detect-webroot.sh "/home/randomly-named-site-22222/site"
assert_contains "$OUT" "WEBROOT_DETECTED=no"

# ── injection-safety smoke ───────────────────────────────────────────────
it "handles path with spaces"
run bin/detect-webroot.sh "/www/wwwroot/site with space"
assert_contains "$OUT" "WEBROOT_DETECTED=yes"

it "handles path with single quote"
run bin/detect-webroot.sh "/www/wwwroot/site's"
assert_contains "$OUT" "WEBROOT_DETECTED=yes"

summary
