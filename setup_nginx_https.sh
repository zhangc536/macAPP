#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
REMOTE_DIR="${REMOTE_DIR:-/var/www/macapp/downloads}"
PUBLIC_PATH_PREFIX="${PUBLIC_PATH_PREFIX:-/downloads}"
SITE_NAME="${SITE_NAME:-macapp}"

if [[ -z "$DOMAIN" ]]; then
  echo "Missing DOMAIN. Example: DOMAIN=your.domain.com"
  exit 1
fi
if [[ -z "$EMAIL" ]]; then
  echo "Missing EMAIL. Example: EMAIL=you@domain.com"
  exit 1
fi
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root. Example: sudo DOMAIN=... EMAIL=... $0"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y nginx ufw

mkdir -p "$REMOTE_DIR"
chown -R www-data:www-data "$(dirname "$REMOTE_DIR")"
chmod -R 755 "$(dirname "$REMOTE_DIR")"

ufw --force enable
ufw allow OpenSSH
ufw allow "Nginx Full"

site_available="/etc/nginx/sites-available/${SITE_NAME}.conf"
site_enabled="/etc/nginx/sites-enabled/${SITE_NAME}.conf"

cat >"$site_available" <<EOF
server {
  listen 80;
  server_name ${DOMAIN};

  location ${PUBLIC_PATH_PREFIX}/ {
    alias ${REMOTE_DIR%/}/;
    try_files \$uri =404;
    add_header Cache-Control "no-store" always;
  }
}
EOF

rm -f /etc/nginx/sites-enabled/default || true
ln -sf "$site_available" "$site_enabled"

nginx -t
systemctl enable --now nginx
systemctl reload nginx

apt-get install -y certbot python3-certbot-nginx

certbot --nginx \
  -d "$DOMAIN" \
  --non-interactive \
  --agree-tos \
  -m "$EMAIL" \
  --redirect

nginx -t
systemctl reload nginx

echo "Ready:"
echo "  https://${DOMAIN}${PUBLIC_PATH_PREFIX}/"
