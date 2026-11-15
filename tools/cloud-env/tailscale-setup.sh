#!/usr/bin/env bash
# Claude Code cloud environment: join the tailnet so the session can reach
# Home Assistant (tailnet node named by HA_HOST, default "homeassistant", port 8123).
# Paste the whole file into the cloud environment's setup script; keep both in sync.
#
# No secret is stored here: the auth key is minted at runtime through
# api.tailscale.com, whose credentials the cloud proxy injects. The key is
# single-use, ephemeral, pre-authorized and expires after 10 minutes; the node
# keeps its state in memory, so it disappears from the tailnet with the container.
set -uo pipefail

if ! command -v tailscale >/dev/null 2>&1; then
  . /etc/os-release
  curl -fsSL "https://pkgs.tailscale.com/stable/${ID}/${VERSION_CODENAME}.noarmor.gpg" \
    -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL "https://pkgs.tailscale.com/stable/${ID}/${VERSION_CODENAME}.tailscale-keyring.list" \
    -o /etc/apt/sources.list.d/tailscale.list
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tailscale
fi

cat > /usr/local/bin/tailnet-up <<'EOF'
#!/usr/bin/env bash
# Idempotent: start tailscaled if needed, then join the tailnet with a fresh key.
set -euo pipefail
SOCK=/run/tailscale/tailscaled.sock
TS="tailscale --socket=$SOCK"
if $TS status >/dev/null 2>&1; then $TS status; exit 0; fi

mkdir -p /run/tailscale
if ! pgrep -x tailscaled >/dev/null; then
  if [ -c /dev/net/tun ]; then
    MODE=(--tun=tailscale0)
  else  # no TUN device: userspace mode, reach the tailnet via SOCKS5/HTTP proxy on :1055
    MODE=(--tun=userspace-networking --socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1055)
  fi
  # tailscaled honours HTTPS_PROXY for control-plane and DERP (443) traffic.
  nohup tailscaled --state=mem: --socket="$SOCK" "${MODE[@]}" >>/var/log/tailscaled.log 2>&1 &
  for _ in $(seq 40); do [ -S "$SOCK" ] && break; sleep 0.25; done
fi

KEY=$(curl -fsS -X POST https://api.tailscale.com/api/v2/tailnet/-/keys \
  -H 'Content-Type: application/json' \
  -d '{"capabilities":{"devices":{"create":{"reusable":false,"ephemeral":true,"preauthorized":true}}},"expirySeconds":600,"description":"claude-cloud-session"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["key"])')

$TS up --authkey="$KEY" --hostname="${TS_HOSTNAME:-claude-cloud}" --accept-routes --accept-dns=false --timeout=60s
$TS ping -c 1 homeassistant || true
EOF
chmod 755 /usr/local/bin/tailnet-up

# Home Assistant credentials: the long-lived token lives in Cloudflare Workers KV
# (namespace "kv", key "HA_TOKEN"), read through the proxy-injected Cloudflare
# credential and kept only in a 0600 file inside the container.
cat > /usr/local/bin/ha-env <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077
ENV_FILE=/root/.config/ha-alerts/ha.env
[ -s "$ENV_FILE" ] && exit 0
CF=https://api.cloudflare.com/client/v4
ACCOUNT=$(curl -fsS "$CF/accounts" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"][0]["id"])')
NS=$(curl -fsS "$CF/accounts/$ACCOUNT/storage/kv/namespaces?per_page=100" \
  | python3 -c 'import json,sys; print(next(n["id"] for n in json.load(sys.stdin)["result"] if n["title"] == "kv"))')
TOKEN=$(curl -fsS "$CF/accounts/$ACCOUNT/storage/kv/namespaces/$NS/values/HA_TOKEN")
mkdir -p "$(dirname "$ENV_FILE")"
printf 'HA_TOKEN=%s\n' "$TOKEN" > "$ENV_FILE"
EOF
chmod 755 /usr/local/bin/ha-env

# Usage: ha-api <path> [curl args...]   e.g. ha-api /api/config
cat > /usr/local/bin/ha-api <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
/usr/local/bin/ha-env
pgrep -x tailscaled >/dev/null || /usr/local/bin/tailnet-up >/dev/null 2>&1 || true
set -a; . /root/.config/ha-alerts/ha.env; set +a
# The HA address is looked up on the tailnet at each call, never stored.
HA_URL=${HA_URL:-http://$(tailscale --socket=/run/tailscale/tailscaled.sock ip -4 "${HA_HOST:-homeassistant}"):8123}
p=$1; shift
exec curl -sS --noproxy '*' --max-time "${HA_TIMEOUT:-60}" \
  -H "Authorization: Bearer $HA_TOKEN" -H 'Content-Type: application/json' "$@" "$HA_URL$p"
EOF
chmod 755 /usr/local/bin/ha-api

# Never block the session start: if this fails here, run `tailnet-up` in the session.
/usr/local/bin/tailnet-up || echo "tailnet-up failed during setup; run it from the session" >&2
/usr/local/bin/ha-env || echo "ha-env failed during setup; ha-api retries it on first use" >&2
exit 0
