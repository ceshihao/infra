#!/usr/bin/env bash
# Alibaba Cloud ECS user_data — executed on nomad clickhouse node startup.
# Mirrors iac/provider-aws/modules/nodepool-clickhouse/scripts/start-clickhouse.sh.
#
# Key differences (vs AWS):
#   1. Data disk location:
#        AWS  EBS volume id lookup via nvme: /dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_<vol-id>
#        Ali  AlibabaCloud ECS uses by-id symlink: /dev/disk/by-id/virtio-${DISK_ID}
#             (DISK_ID injected by templatefile, alicloud_ecs_disk.clickhouse[i].id with d- prefix stripped)
#   2. ossutil to download scripts + acr-credential-helper

set -euo pipefail

PS4='[\D{%Y-%m-%d %H:%M:%S}] '
set -x

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

ulimit -n 1048576

# --- Mount stateful disk ---
# Needed for ClickHouse to persist data across instance replacement
DISK_BY_ID="/dev/disk/by-id/virtio-${DISK_ID}"
MOUNT_POINT="/clickhouse"
TIMEOUT=300 # 5 minutes
INTERVAL=5  # seconds

echo "Waiting for data disk $DISK_BY_ID to appear..."

SECONDS_WAITED=0
DISK=""

while [[ $SECONDS_WAITED -lt $TIMEOUT ]]; do
  if [[ -e "$DISK_BY_ID" ]]; then
    DISK=$(readlink -f "$DISK_BY_ID")
    echo "Found disk: $DISK_BY_ID -> $DISK"
    break
  fi
  sleep $INTERVAL
  SECONDS_WAITED=$((SECONDS_WAITED + INTERVAL))
done

if [[ -z "$DISK" ]]; then
  echo "ERROR: data disk $DISK_BY_ID not found after $${TIMEOUT}s"
  exit 1
fi

# Create filesystem if not already formatted
if ! blkid "$DISK"; then
  echo "No filesystem found on $DISK, creating XFS filesystem..."
  mkfs.xfs -f -b size=4096 "$DISK"
fi

mkdir -p "$MOUNT_POINT"
mount -o noatime "$DISK" "$MOUNT_POINT"
echo "Mounted $DISK at $MOUNT_POINT"

# -------------------------------

sudo tee -a /etc/sysctl.conf <<EOF
# Increase the maximum number of socket connections
net.core.somaxconn = 65535

# Increase the maximum number of backlogged connections
net.core.netdev_max_backlog = 65535

# Increase maximum number of TCP sockets
net.ipv4.tcp_max_syn_backlog = 65535
EOF
sudo sysctl -p

# Download startup scripts from OSS setup bucket
ossutil cp -f "oss://${SCRIPTS_BUCKET}/run-consul-${RUN_CONSUL_FILE_HASH}.sh" /opt/consul/bin/run-consul.sh
ossutil cp -f "oss://${SCRIPTS_BUCKET}/run-nomad-${RUN_NOMAD_FILE_HASH}.sh"   /opt/nomad/bin/run-nomad.sh
chmod +x /opt/consul/bin/run-consul.sh /opt/nomad/bin/run-nomad.sh

# ACR EE credential helper configuration.
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

# Consul DNS for systemd-resolved
mkdir -p /etc/systemd/resolved.conf.d/
cat <<EOF >/etc/systemd/resolved.conf.d/consul.conf
[Resolve]
DNS=127.0.0.1:8600
DNSSEC=false
Domains=~consul
EOF

# Expose systemd-resolved DNS stub on docker0 (172.17.0.1) so that containers can resolve *.consul.
cat <<EOF >/etc/systemd/resolved.conf.d/docker.conf
[Resolve]
DNSStubListener=yes
DNSStubListenerExtra=172.17.0.1
EOF
systemctl restart systemd-resolved

# CNI plugins are pre-installed during disk image build.

/opt/consul/bin/run-consul.sh --client \
    --consul-token         "${CONSUL_TOKEN}" \
    --cluster-tag-name     "${CLUSTER_TAG_NAME}" \
    --cluster-tag-value    "${CLUSTER_TAG_VALUE}" \
    --enable-gossip-encryption \
    --gossip-encryption-key "${CONSUL_GOSSIP_ENCRYPTION_KEY}" \
    --dns-request-token    "${CONSUL_DNS_REQUEST_TOKEN}" &

/opt/nomad/bin/run-nomad.sh --client --consul-token "${CONSUL_TOKEN}" --node-pool "${NODE_POOL}" &
