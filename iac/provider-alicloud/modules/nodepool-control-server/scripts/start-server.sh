#!/bin/bash
# Alibaba Cloud ECS user_data — executed on nomad control-server node startup.
# Mirrors iac/provider-aws/modules/nodepool-control-server/scripts/start-server.sh.
#
# Key differences (vs AWS):
#   1. metadata: 169.254.169.254 + IMDSv2 -> 100.100.100.200 (no token)
#   2. script download: aws s3 cp -> ossutil cp (ECS RAM Role auto-signs; ossutil pre-installed in disk image)
#   3. consul/nomad retry-join provider=aws -> provider=aliyun (inside run-consul.sh / run-nomad.sh)

set -e

# Send the log output from this script to user-data.log, syslog, and the console
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

ulimit -n 65536
export GOMAXPROCS=$(nproc)

# Download run-consul.sh / run-nomad.sh from OSS setup bucket (hash suffix triggers updates).
# ossutil auto-fetches STS from ECS metadata 100.100.100.200/latest/meta-data/Ram/security-credentials/<role>.
ossutil cp -f "oss://${SCRIPTS_BUCKET}/run-consul-${RUN_CONSUL_FILE_HASH}.sh" /opt/consul/bin/run-consul.sh
ossutil cp -f "oss://${SCRIPTS_BUCKET}/run-nomad-${RUN_NOMAD_FILE_HASH}.sh"   /opt/nomad/bin/run-nomad.sh

chmod +x /opt/consul/bin/run-consul.sh /opt/nomad/bin/run-nomad.sh

/opt/consul/bin/run-consul.sh --server \
  --cluster-tag-name  "${CLUSTER_TAG_NAME}" \
  --cluster-tag-value "${CLUSTER_TAG_VALUE}" \
  --consul-token      "${CONSUL_TOKEN}" \
  --enable-gossip-encryption \
  --gossip-encryption-key "${CONSUL_GOSSIP_ENCRYPTION_KEY}"

/opt/nomad/bin/run-nomad.sh --server \
  --num-servers  "${NUM_SERVERS}" \
  --consul-token "${CONSUL_TOKEN}" \
  --nomad-token  "${NOMAD_TOKEN}"
