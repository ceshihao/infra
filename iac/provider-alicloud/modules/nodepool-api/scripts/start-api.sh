#!/usr/bin/env bash
# Alibaba Cloud ECS user_data — executed on nomad api node startup.
# Mirrors iac/provider-aws/modules/nodepool-api/scripts/start-api.sh.
#
# Key differences (vs AWS):
#   1. metadata 100.100.100.200 (no token)
#   2. ossutil to download startup scripts
#   3. ACR EE login: aws ecr get-login-password -> aliyun cr GetAuthorizationToken
#      Docker credHelper uses acr-credential-helper (pre-installed in disk image),
#      falls back to aliyun CLI direct docker login on failure.

set -euo pipefail

PS4='[\D{%Y-%m-%d %H:%M:%S}] '
set -x

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

ulimit -n 1048576
export GOMAXPROCS=$(nproc)

sudo tee -a /etc/sysctl.conf <<EOF
# Increase the maximum number of socket connections
net.core.somaxconn = 65535

# Increase the maximum number of backlogged connections
net.core.netdev_max_backlog = 65535

# Increase maximum number of TCP sockets
net.ipv4.tcp_max_syn_backlog = 65535
EOF
sudo sysctl -p

# Download startup scripts from OSS setup bucket (ECS RAM Role auto-signs requests)
ossutil cp -f "oss://${SCRIPTS_BUCKET}/run-consul-${RUN_CONSUL_FILE_HASH}.sh" /opt/consul/bin/run-consul.sh
ossutil cp -f "oss://${SCRIPTS_BUCKET}/run-nomad-${RUN_NOMAD_FILE_HASH}.sh"   /opt/nomad/bin/run-nomad.sh
chmod +x /opt/consul/bin/run-consul.sh /opt/nomad/bin/run-nomad.sh

# Docker login to ACR EE: acr-credential-helper (pre-installed in disk image) makes docker pull
# automatically obtain STS tokens on demand. Equivalent to AWS ecr-login credHelper.
# The helper reads ACR EE instance id / region from /etc/aliyun-acr-helper.conf and calls cr:GetAuthorizationToken.
mkdir -p /etc
cat <<EOF >/etc/aliyun-acr-helper.conf
ACR_INSTANCE_ID=${ALIBABA_CLOUD_ACR_INSTANCE_ID}
ACR_REGION=${ALIBABA_CLOUD_REGION}
EOF
chmod 0644 /etc/aliyun-acr-helper.conf

mkdir -p /root/docker
cat <<EOF >/root/docker/config.json
{
    "credHelpers": {
        "${ALIBABA_CLOUD_ACR_ACCOUNT_REPOSITORY_DOMAIN}": "acr-credential-helper"
    }
}
EOF

# Consul DNS for systemd-resolved: route *.consul queries to 127.0.0.1:8600
mkdir -p /etc/systemd/resolved.conf.d/
cat <<EOF >/etc/systemd/resolved.conf.d/consul.conf
[Resolve]
DNS=127.0.0.1:8600
DNSSEC=false
Domains=~consul
DNSStubListener=yes
DNSStubListenerExtra=172.17.0.1
EOF
systemctl restart systemd-resolved

/opt/consul/bin/run-consul.sh --client \
    --consul-token         "${CONSUL_TOKEN}" \
    --cluster-tag-name     "${CLUSTER_TAG_NAME}" \
    --cluster-tag-value    "${CLUSTER_TAG_VALUE}" \
    --enable-gossip-encryption \
    --gossip-encryption-key "${CONSUL_GOSSIP_ENCRYPTION_KEY}" \
    --dns-request-token    "${CONSUL_DNS_REQUEST_TOKEN}" &

/opt/nomad/bin/run-nomad.sh --client --consul-token "${CONSUL_TOKEN}" --node-pool "${NODE_POOL}" &
