#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-YourApp}"
ROOT_DOMAIN="${ROOT_DOMAIN:-}"
SUBDOMAIN="${SUBDOMAIN:-}"
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"

CF_API_TOKEN="${CF_API_TOKEN:-}"
CF_ZONE_ID="${CF_ZONE_ID:-}"
CF_PROXIED="${CF_PROXIED:-true}"

PUBLISH_DIR="${PUBLISH_DIR:-/srv/macapp/downloads}"
INCOMING_DIR="${INCOMING_DIR:-/root/dmg}"
PUBLIC_PATH_PREFIX="${PUBLIC_PATH_PREFIX:-/downloads}"
UFW_ENABLE="${UFW_ENABLE:-0}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请用 root 运行：sudo bash $0"
  exit 1
fi

if [[ -z "$DOMAIN" ]]; then
  if [[ -z "$ROOT_DOMAIN" || -z "$SUBDOMAIN" ]]; then
    echo "Missing DOMAIN or (ROOT_DOMAIN + SUBDOMAIN)"
    exit 1
  fi
  DOMAIN="${SUBDOMAIN}.${ROOT_DOMAIN}"
fi
if [[ -z "$EMAIL" ]]; then
  echo "Missing EMAIL"
  exit 1
fi

if [[ -n "$CF_API_TOKEN" && -z "$CF_ZONE_ID" ]]; then
  echo "Missing CF_ZONE_ID"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y nginx certbot jq curl python3 p7zip-full
if [[ -n "$CF_API_TOKEN" ]]; then
  apt-get install -y python3-certbot-dns-cloudflare
else
  apt-get install -y python3-certbot-nginx
fi

mkdir -p "$PUBLISH_DIR" "$INCOMING_DIR"
chown -R www-data:www-data "$(dirname "$PUBLISH_DIR")"
chmod -R 755 "$(dirname "$PUBLISH_DIR")"

if [[ "$UFW_ENABLE" == "1" ]]; then
  apt-get install -y ufw
  ufw --force enable
  ufw allow OpenSSH
  ufw allow "Nginx Full"
fi

get_ip() {
  local ver="$1"
  if [[ "$ver" == "4" ]]; then
    curl -4fsS https://api.ipify.org || curl -4fsS https://ifconfig.me || true
  else
    curl -6fsS https://api64.ipify.org || curl -6fsS https://ifconfig.me || true
  fi
}

api() {
  curl -fsS -H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json" "$@"
}

upsert_dns() {
  local type="$1" ip="$2"
  [[ -z "$ip" ]] && return 0
  local existing_id
  existing_id="$(api "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=${type}&name=${DOMAIN}" | jq -r '.result[0].id // empty')"
  local payload
  payload="$(jq -n --arg type "$type" --arg name "$DOMAIN" --arg content "$ip" --argjson proxied "$( [[ "$CF_PROXIED" == "true" ]] && echo true || echo false )" '{type:$type,name:$name,content:$content,ttl:120,proxied:$proxied}')"
  if [[ -n "$existing_id" ]]; then
    api -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${existing_id}" --data "$payload" >/dev/null
  else
    api -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" --data "$payload" >/dev/null
  fi
}

if [[ -n "$CF_API_TOKEN" ]]; then
  IPV4="$(get_ip 4 || true)"
  IPV6="$(get_ip 6 || true)"
  [[ -n "${IPV4:-}" ]] && upsert_dns "A" "$IPV4" || true
  [[ -n "${IPV6:-}" ]] && upsert_dns "AAAA" "$IPV6" || true
fi

site="/etc/nginx/sites-available/${DOMAIN}.conf"
cat >"$site" <<NGHTTP
server {
  listen 80;
  listen [::]:80;
  server_name ${DOMAIN};

  location ${PUBLIC_PATH_PREFIX}/ {
    alias ${PUBLISH_DIR%/}/;
    try_files \$uri =404;
    add_header Cache-Control "no-store" always;
  }

  location / {
    return 404;
  }
}
NGHTTP

ln -sf "$site" "/etc/nginx/sites-enabled/${DOMAIN}.conf"
rm -f /etc/nginx/sites-enabled/default || true
nginx -t
systemctl enable --now nginx
systemctl reload nginx

if [[ -n "$CF_API_TOKEN" ]]; then
  install -m 600 -o root -g root /dev/null /root/cf.ini
  cat >/root/cf.ini <<EOF
dns_cloudflare_api_token = ${CF_API_TOKEN}
EOF
  chmod 600 /root/cf.ini

  obtain_cert() {
    local wait="$1"
    certbot certonly \
      --dns-cloudflare \
      --dns-cloudflare-credentials /root/cf.ini \
      --dns-cloudflare-propagation-seconds "$wait" \
      -d "$DOMAIN" \
      --agree-tos -m "$EMAIL" --non-interactive
  }

  set +e
  obtain_cert 120
  RET=$?
  if [[ $RET -ne 0 ]]; then
    obtain_cert 300
    RET=$?
  fi
  set -e
  if [[ $RET -ne 0 ]]; then
    echo "证书签发失败，请检查 /var/log/letsencrypt/letsencrypt.log"
    exit 1
  fi
else
  certbot certonly --nginx -d "$DOMAIN" --agree-tos -m "$EMAIL" --non-interactive || {
    echo "证书签发失败，请检查 /var/log/letsencrypt/letsencrypt.log"
    exit 1
  }
fi

cat >"$site" <<'NGHTTPS'
server {
  listen 80;
  listen [::]:80;
  server_name FQDN_REPL;
  return 301 https://$host$request_uri;
}

server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name FQDN_REPL;

  ssl_certificate     /etc/letsencrypt/live/FQDN_REPL/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/FQDN_REPL/privkey.pem;
  ssl_session_timeout 1d;
  ssl_session_cache shared:SSL:10m;
  ssl_protocols TLSv1.2 TLSv1.3;

  location PATH_PREFIX_REPL/ {
    alias PUBLISH_DIR_REPL/;
    try_files $uri =404;
    add_header Cache-Control "no-store" always;
  }

  location / {
    return 404;
  }
}
NGHTTPS

sed -i "s/FQDN_REPL/${DOMAIN}/g" "$site"
sed -i "s#PATH_PREFIX_REPL#${PUBLIC_PATH_PREFIX}#g" "$site"
sed -i "s#PUBLISH_DIR_REPL#${PUBLISH_DIR%/}#g" "$site"
nginx -t
systemctl reload nginx

install -m 755 -o root -g root /dev/null /usr/local/bin/macapp-publish.sh
cat >/usr/local/bin/macapp-publish.sh <<'PUBLISH'
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-YourApp}"
DOMAIN="${DOMAIN:-}"
PUBLIC_PATH_PREFIX="${PUBLIC_PATH_PREFIX:-/downloads}"
PUBLISH_DIR="${PUBLISH_DIR:-/srv/macapp/downloads}"
INCOMING_DIR="${INCOMING_DIR:-/root/dmg}"

if [[ -z "$DOMAIN" ]]; then
  echo "Missing DOMAIN"
  exit 1
fi

latest_dmg() {
  local latest
  latest="$(ls -t "${INCOMING_DIR%/}"/*.dmg 2>/dev/null | head -n 1 || true)"
  [[ -n "$latest" ]] || return 1
  printf "%s" "$latest"
}

sha256_of_file() {
  python3 - "$1" <<'PY'
import hashlib
import sys

path = sys.argv[1]
h = hashlib.sha256()
with open(path, "rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        h.update(chunk)
print(h.hexdigest())
PY
}

extract_version() {
  python3 - "$1" <<'PY'
import re
import sys

stem = sys.argv[1]
matches = re.findall(r"\d+(?:\.\d+)+", stem)
if matches:
    print(matches[-1])
PY
}

version_from_dmg() {
  local dmg_path="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d -t macapp_dmg.XXXXXX)"
  trap 'rm -rf "$tmp_dir"' RETURN

  if ! command -v 7z >/dev/null 2>&1; then
    return 1
  fi

  7z x -y -o"$tmp_dir" "$dmg_path" >/dev/null 2>&1 || return 1

  python3 - "$tmp_dir" <<'PY'
import os
import plistlib
import sys

root = sys.argv[1]
candidates = []
for base, _, files in os.walk(root):
    if "Info.plist" in files and ".app/Contents" in base.replace("\\", "/"):
        candidates.append(os.path.join(base, "Info.plist"))

for path in sorted(candidates, key=len):
    try:
        with open(path, "rb") as f:
            plist = plistlib.load(f)
        v = plist.get("CFBundleShortVersionString") or plist.get("CFBundleVersion")
        if isinstance(v, str) and v.strip():
            print(v.strip())
            break
    except Exception:
        continue
PY
}

mtime_version() {
  python3 - "$1" <<'PY'
import datetime
import os
import sys

path = sys.argv[1]
ts = os.path.getmtime(path)
dt = datetime.datetime.utcfromtimestamp(ts)
print(dt.strftime("%Y.%m.%d.%H%M%S"))
PY
}

dmg_path="$(latest_dmg || true)"
if [[ -z "$dmg_path" ]]; then
  exit 0
fi

mkdir -p "$PUBLISH_DIR"

current_hash="$(sha256_of_file "$dmg_path")"
hash_file="${PUBLISH_DIR%/}/.last_sha256"
if [[ -f "$hash_file" ]]; then
  last_hash="$(cat "$hash_file" || true)"
  if [[ "$current_hash" == "$last_hash" ]]; then
    exit 0
  fi
fi

stem="$(basename "$dmg_path")"
stem="${stem%.dmg}"
version="$(extract_version "$stem" || true)"
if [[ -z "$version" ]]; then
  version="$(version_from_dmg "$dmg_path" || true)"
fi
if [[ -z "$version" ]]; then
  version="$(mtime_version "$dmg_path" || true)"
fi
if [[ -z "$version" ]]; then
  version="$(date -u +"%Y.%m.%d.%H%M%S")"
fi

notes_file="${INCOMING_DIR%/}/release_notes.txt"
notes=""
if [[ -f "$notes_file" ]]; then
  notes="$(cat "$notes_file")"
fi

released_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
url="https://${DOMAIN}${PUBLIC_PATH_PREFIX%/}/${APP_NAME}.dmg"

tmp_dmg="${PUBLISH_DIR%/}/${APP_NAME}.dmg.part"
cp -f "$dmg_path" "$tmp_dmg"
mv -f "$tmp_dmg" "${PUBLISH_DIR%/}/${APP_NAME}.dmg"

python3 - "$version" "$url" "$notes" "$released_at" >"${PUBLISH_DIR%/}/${APP_NAME}.json.part" <<'PY'
import json
import sys

version, url, release_notes, released_at = sys.argv[1:5]
payload = {
    "version": version,
    "url": url,
    "releaseNotes": release_notes,
    "releasedAt": released_at,
}
sys.stdout.write(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
PY
mv -f "${PUBLISH_DIR%/}/${APP_NAME}.json.part" "${PUBLISH_DIR%/}/${APP_NAME}.json"

echo "$current_hash" >"$hash_file"
PUBLISH

chmod 755 /usr/local/bin/macapp-publish.sh

cat >/etc/systemd/system/macapp-publish.service <<UNIT
[Unit]
Description=Publish macOS DMG and metadata

[Service]
Type=oneshot
Environment=APP_NAME=${APP_NAME}
Environment=DOMAIN=${DOMAIN}
Environment=PUBLIC_PATH_PREFIX=${PUBLIC_PATH_PREFIX}
Environment=PUBLISH_DIR=${PUBLISH_DIR}
Environment=INCOMING_DIR=${INCOMING_DIR}
ExecStart=/usr/local/bin/macapp-publish.sh
UNIT

cat >/etc/systemd/system/macapp-publish.path <<UNIT
[Unit]
Description=Watch DMG incoming directory

[Path]
PathExistsGlob=${INCOMING_DIR%/}/*.dmg
PathModified=${INCOMING_DIR}
Unit=macapp-publish.service

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now macapp-publish.path
systemctl start macapp-publish.service || true

systemctl enable certbot.timer >/dev/null 2>&1 || true
systemctl start certbot.timer >/dev/null 2>&1 || true

echo "OK"
echo "INCOMING_DIR=${INCOMING_DIR}"
echo "PUBLISH_DIR=${PUBLISH_DIR}"
echo "URL=https://${DOMAIN}${PUBLIC_PATH_PREFIX%/}/${APP_NAME}.dmg"
echo "META=https://${DOMAIN}${PUBLIC_PATH_PREFIX%/}/${APP_NAME}.json"
