#!/usr/bin/env bash
# Install the Aliyun ACR EE docker credential helper to /usr/local/bin/.
#
# When Docker daemon pulls an image, it invokes docker-credential-<name> based on
# the credHelpers field in docker config.json. Here name = "acr-credential-helper",
# so the binary is named docker-credential-acr-credential-helper.
#
# Protocol (github.com/docker/docker-credential-helpers):
#   action = get   : stdin = registry hostname  ->  stdout = JSON {ServerURL,Username,Secret}
#   action = store : stdin = JSON {ServerURL,Username,Secret}  ->  stdout = (empty)
#   action = erase : stdin = registry hostname  ->  stdout = (empty)
#   action = list  :                             stdout = JSON {ServerURL: Username}
#
# Configuration (/etc/aliyun-acr-helper.conf, written by ECS user_data):
#   ACR_INSTANCE_ID=cri-xxx     # required, ACR EE instance id
#   ACR_REGION=cn-hangzhou      # optional, defaults to value from ECS metadata
#
# Credentials: relies on ECS instance-bound RAM Role (aliyun CLI auto-signs via
#       100.100.100.200/latest/meta-data/Ram/security-credentials/<role> to get STS).

set -euo pipefail

readonly HELPER_PATH="/usr/local/bin/docker-credential-acr-credential-helper"

sudo apt-get update
sudo apt-get install -y curl jq

sudo tee "$HELPER_PATH" > /dev/null <<'HELPER'
#!/usr/bin/env bash
# Docker credential helper for Alibaba Cloud Container Registry (ACR EE).
# Installed at /usr/local/bin/, invoked by docker daemon on pull.
set -euo pipefail

ACTION="${1:-}"
CONF=/etc/aliyun-acr-helper.conf

empty_response() {
  printf '{"ServerURL":"","Username":"","Secret":""}\n'
}

case "$ACTION" in
  get) ;;
  store|erase)
    # We only serve 'get'; other actions return empty silently to avoid docker daemon errors.
    cat >/dev/null || true
    exit 0
    ;;
  list)
    printf '{}\n'
    exit 0
    ;;
  *)
    empty_response
    exit 0
    ;;
esac

# stdin is the registry hostname passed by docker (used as ServerURL in response).
SERVER="$(cat || true)"

if [[ ! -r "$CONF" ]]; then
  empty_response
  exit 0
fi

# shellcheck disable=SC1090
. "$CONF"

if [[ -z "${ACR_INSTANCE_ID:-}" ]]; then
  empty_response
  exit 0
fi

# region defaults to ECS metadata when not set.
if [[ -z "${ACR_REGION:-}" ]]; then
  ACR_REGION="$(curl --silent --show-error --fail --max-time 3 \
    http://100.100.100.200/latest/meta-data/region-id || true)"
fi

if [[ -z "$ACR_REGION" ]]; then
  empty_response
  exit 0
fi

# aliyun CLI on ECS auto-signs with RAM Role (no AK/SK configuration needed).
RESP="$(aliyun cr GetAuthorizationToken \
  --InstanceId "$ACR_INSTANCE_ID" \
  --region "$ACR_REGION" \
  --version 2018-12-01 2>/dev/null || true)"

if [[ -z "$RESP" ]]; then
  empty_response
  exit 0
fi

USER="$(printf '%s' "$RESP" | jq -r '.TempUsername // empty')"
SECRET="$(printf '%s' "$RESP" | jq -r '.AuthorizationToken // empty')"

if [[ -z "$USER" || -z "$SECRET" ]]; then
  empty_response
  exit 0
fi

# Use jq to safely emit JSON (escape any quotes in SERVER/USER/SECRET).
jq -nc \
  --arg server "$SERVER" \
  --arg user   "$USER" \
  --arg secret "$SECRET" \
  '{ServerURL: $server, Username: $user, Secret: $secret}'
HELPER

sudo chmod 0755 "$HELPER_PATH"

echo "Installed Aliyun ACR docker credential helper at $HELPER_PATH"
