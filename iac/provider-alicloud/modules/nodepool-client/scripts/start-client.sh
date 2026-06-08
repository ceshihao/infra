#!/usr/bin/env bash
# Alibaba Cloud ECS user_data — executed on nomad client/build node startup.
# Mirrors iac/provider-aws/modules/nodepool-client/scripts/start-client.sh.
#
# Key differences (vs AWS):
#   1. nested-virt check (fail-fast):
#        Non-bare-metal types don't expose vmx/svm flags; firecracker won't start.
#        If ${NESTED_VIRTUALIZATION}=true but /proc/cpuinfo lacks the flag, exit 1 immediately.
#   2. OSS mount: s3fs -> ossfs (aliyun ossfs, auto-uses ECS RAM Role for STS)
#   3. ossutil to download scripts + acr-credential-helper

set -euo pipefail

PS4='[\D{%Y-%m-%d %H:%M:%S}] '
set -x

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# ---- nested virtualization fail-fast ----
if [ "${NESTED_VIRTUALIZATION}" = "true" ]; then
  if ! grep -qE '^flags.*\b(vmx|svm)\b' /proc/cpuinfo; then
    echo "[FATAL] nested KVM unavailable on this instance type." >&2
    echo "        Choose Alibaba ECS bare-metal family (ebmg7/ebmgn7/ebmc7a/...)." >&2
    exit 1
  fi
fi

mkdir -p /orchestrator
mkdir -p /orchestrator/sandbox
mkdir -p /orchestrator/template
mkdir -p /orchestrator/build

# Add swapfile
SWAPFILE="/swapfile"
fallocate -l 100G $SWAPFILE
chmod 600 $SWAPFILE
mkswap $SWAPFILE
swapon $SWAPFILE

# Make swapfile persistent
echo "$SWAPFILE none swap sw 0 0" | tee -a /etc/fstab

# Set swap settings
sysctl vm.swappiness=10
sysctl vm.vfs_cache_pressure=50

# Add tmpfs for snapshotting
mkdir -p /mnt/snapshot-cache
mount -t tmpfs -o size=65G tmpfs /mnt/snapshot-cache

ulimit -n 1048576
export GOMAXPROCS=$(nproc)

tee -a /etc/sysctl.conf <<EOF
# Increase the maximum number of socket connections
net.core.somaxconn = 65535

# Increase the maximum number of backlogged connections
net.core.netdev_max_backlog = 65535

# Increase maximum number of TCP sockets
net.ipv4.tcp_max_syn_backlog = 65535

# Increase the maximum number of memory map areas
vm.max_map_count=1048576

EOF
sysctl -p

echo "Disabling inotify for NBD devices"
cat <<EOH >/etc/udev/rules.d/97-nbd-device.rules
# Disable inotify watching of change events for NBD devices
ACTION=="add|change", KERNEL=="nbd*", OPTIONS:="nowatch"
EOH

udevadm control --reload-rules
udevadm trigger

# Load the nbd module with 4096 devices
modprobe nbd nbds_max=4096

# Create the directory for the fc mounts
mkdir -p /fc-vm

# AlibabaCloud ossfs mount credentials: ECS RAM Role + STS (disk image configures /etc/passwd-ossfs
# empty + -o ram_role=<role-name>). This relies on the disk image setup phase having written the
# RAM role to /etc/sysconfig/ossfs.role or similar; ossfs itself supports -o ram_role=NAME to
# pull STS directly.
OSS_ENDPOINT="oss-${ALIBABA_CLOUD_REGION}-internal.aliyuncs.com"

# Mount envd buckets
envd_dir="/fc-envd"
mkdir -p $envd_dir
ossfs "${FC_ENV_PIPELINE_BUCKET_NAME}" "$envd_dir" \
  -o url="https://$OSS_ENDPOINT" -o ram_role="${OSSFS_RAM_ROLE}" \
  -o allow_other -o umask=000 -o nonempty -o enable_noobj_cache

# Mount kernels
kernels_dir="/fc-kernels"
mkdir -p $kernels_dir
ossfs "${FC_KERNELS_BUCKET_NAME}" "$kernels_dir" \
  -o url="https://$OSS_ENDPOINT" -o ram_role="${OSSFS_RAM_ROLE}" \
  -o allow_other -o umask=000 -o nonempty -o enable_noobj_cache

# Mount FC versions
fc_versions_dir="/fc-versions"
mkdir -p $fc_versions_dir
ossfs "${FC_VERSIONS_BUCKET_NAME}" "$fc_versions_dir" \
  -o url="https://$OSS_ENDPOINT" -o ram_role="${OSSFS_RAM_ROLE}" \
  -o allow_other -o umask=000 -o nonempty -o enable_noobj_cache

# Mount busybox
busybox_dir="/fc-busybox"
mkdir -p $busybox_dir
ossfs "${FC_BUSYBOX_BUCKET_NAME}" "$busybox_dir" \
  -o url="https://$OSS_ENDPOINT" -o ram_role="${OSSFS_RAM_ROLE}" \
  -o allow_other -o umask=000 -o nonempty -o enable_noobj_cache

# Download startup scripts from OSS setup bucket
ossutil cp -f "oss://${SCRIPTS_BUCKET}/run-consul-${RUN_CONSUL_FILE_HASH}.sh" /opt/consul/bin/run-consul.sh
ossutil cp -f "oss://${SCRIPTS_BUCKET}/run-nomad-${RUN_NOMAD_FILE_HASH}.sh"   /opt/nomad/bin/run-nomad.sh
chmod +x /opt/consul/bin/run-consul.sh /opt/nomad/bin/run-nomad.sh

mkdir -p /root/docker
cat <<EOF >/root/docker/config.json
{
    "credHelpers": {
        "${ALIBABA_CLOUD_ACR_ACCOUNT_REPOSITORY_DOMAIN}": "acr-credential-helper"
    }
}
EOF

# ACR EE credential helper configuration. The helper reads instance id / region from here
# and calls cr:GetAuthorizationToken.
mkdir -p /etc
cat <<EOF >/etc/aliyun-acr-helper.conf
ACR_INSTANCE_ID=${ALIBABA_CLOUD_ACR_INSTANCE_ID}
ACR_REGION=${ALIBABA_CLOUD_REGION}
EOF
chmod 0644 /etc/aliyun-acr-helper.conf

mkdir -p /etc/systemd/resolved.conf.d/
cat <<EOF >/etc/systemd/resolved.conf.d/consul.conf
[Resolve]
DNS=127.0.0.1:8600
DNSSEC=false
DNSStubListener=yes
DNSStubListenerExtra=172.17.0.1
EOF
sync

# Set up huge pages
echo "[Setting up huge pages]"
mkdir -p /mnt/hugepages
mount -t hugetlbfs none /mnt/hugepages

available_ram=$(grep MemTotal /proc/meminfo | awk '{print $2}') # in KiB
available_ram=$(($available_ram / 1024))                        # in MiB
echo "- Total memory: $available_ram MiB"

min_normal_ram=$((4 * 1024))                             # 4 GiB
min_normal_percentage_ram=$(($available_ram * 16 / 100)) # 16% of the total memory
max_normal_ram=$((42 * 1024))                            # 42 GiB

max() {
    if (($1 > $2)); then
        echo "$1"
    else
        echo "$2"
    fi
}

min() {
    if (($1 < $2)); then
        echo "$1"
    else
        echo "$2"
    fi
}

ensure_even() {
    if (($1 % 2 == 0)); then
        echo "$1"
    else
        echo $(($1 - 1))
    fi
}

remove_decimal() {
    echo "$(echo $1 | sed 's/\..*//')"
}

reserved_normal_ram=$(max $min_normal_ram $min_normal_percentage_ram)
reserved_normal_ram=$(min $reserved_normal_ram $max_normal_ram)
echo "- Reserved RAM: $reserved_normal_ram MiB"

hugepages_ram=$(($available_ram - $reserved_normal_ram))
hugepages_ram=$(remove_decimal $hugepages_ram)
hugepages_ram=$(ensure_even $hugepages_ram)
echo "- RAM for hugepages: $hugepages_ram MiB"

hugepage_size_in_mib=2
echo "- Huge page size: $hugepage_size_in_mib MiB"
hugepages=$(($hugepages_ram / $hugepage_size_in_mib))

base_hugepages_percentage=${BASE_HUGEPAGES_PERCENTAGE}
base_hugepages=$(($hugepages * $base_hugepages_percentage / 100))
base_hugepages=$(remove_decimal $base_hugepages)
echo "- Allocating $base_hugepages huge pages ($base_hugepages_percentage%) for base usage"
echo $base_hugepages >/proc/sys/vm/nr_hugepages

overcommitment_hugepages_percentage=$((100 - $base_hugepages_percentage))
overcommitment_hugepages=$(($hugepages * $overcommitment_hugepages_percentage / 100))
overcommitment_hugepages=$(remove_decimal $overcommitment_hugepages)
echo "- Allocating $overcommitment_hugepages huge pages ($overcommitment_hugepages_percentage%) for overcommitment"
echo $overcommitment_hugepages >/proc/sys/vm/nr_overcommit_hugepages

# Start Consul first (in background)
/opt/consul/bin/run-consul.sh --client \
    --consul-token         "${CONSUL_TOKEN}" \
    --cluster-tag-name     "${CLUSTER_TAG_NAME}" \
    --cluster-tag-value    "${CLUSTER_TAG_VALUE}" \
    --enable-gossip-encryption \
    --gossip-encryption-key "${CONSUL_GOSSIP_ENCRYPTION_KEY}" \
    --dns-request-token    "${CONSUL_DNS_REQUEST_TOKEN}" &

# Wait for Consul DNS to start on port 8600
echo "- Waiting for Consul DNS to start on port 8600..."
for i in {1..60}; do
  if nc -z 127.0.0.1 8600 2>/dev/null; then
    echo "- Consul DNS is ready (attempt $i/60)"
    break
  fi
  if [ $i -eq 60 ]; then
    echo "- ERROR: Consul DNS not responding after 60 seconds, exiting..."
    exit 1
  fi
  sleep 1
done

# Restart systemd-resolved AFTER Consul DNS is up so the stub doesn't mark it unreachable.
echo "[Configuring systemd-resolved for Consul DNS]"
systemctl restart systemd-resolved

echo "- Waiting for systemd-resolved to start..."
for i in {1..60}; do
  if host google.com 2>/dev/null; then
    echo "- DNS resolving is ready (attempt $i/60)"
    break
  fi
  if [ $i -eq 60 ]; then
    echo "- ERROR: Systemd-resolved not responding after 60 seconds, exiting..."
    exit 1
  fi
  sleep 1
done
echo "- Flushing DNS caches"
resolvectl flush-caches

/opt/nomad/bin/run-nomad.sh --client \
  --consul-token "${CONSUL_TOKEN}" \
  --node-pool    "${NODE_POOL}" \
  --node-labels  "${NODE_LABELS}" &

# Add alias for ssh-ing to sbx
echo '_sbx_ssh() {
  local address=$(dig @127.0.0.4 $1. A +short 2>/dev/null)
  ssh -o StrictHostKeyChecking=accept-new "root@$address"
}

alias sbx-ssh=_sbx_ssh' >>/etc/profile
