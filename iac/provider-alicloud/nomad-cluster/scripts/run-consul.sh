#!/bin/bash
# Configure and start Consul on an Alibaba Cloud ECS instance.
# Mirrors iac/provider-aws/nomad-cluster/scripts/run-consul.sh.
#
# Key differences (vs AWS):
#   1. metadata service: 169.254.169.254 + IMDSv2 -> 100.100.100.200 (direct GET, no token)
#                        region/zone/instance-id/private-ipv4 each have their own path
#                        tags via 100.100.100.200/latest/meta-data/tags/instance/<key>
#   2. node auto-discovery retry_join: "provider=aws ..." -> "provider=aliyun ..."
#                       Consul has built-in alicloud cloud-auto-join; credentials obtained
#                       automatically via ECS RAM Role.
#   3. ulimit / sysctl / systemd unit identical to AWS version.

set -e

set -x

readonly BASH_COMMONS_DIR="/opt/gruntwork/bash-commons"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly CONSUL_CONFIG_FILE="default.json"
readonly SYSTEMD_CONFIG_PATH="/etc/systemd/system/consul.service"

readonly ALICLOUD_METADATA_URL="http://100.100.100.200/latest/meta-data"
readonly CLUSTER_SIZE_INSTANCE_METADATA_KEY_NAME="cluster-size"

readonly DEFAULT_RAFT_PROTOCOL="3"

readonly DEFAULT_AUTOPILOT_CLEANUP_DEAD_SERVERS="true"
readonly DEFAULT_AUTOPILOT_LAST_CONTACT_THRESHOLD="200ms"
readonly DEFAULT_AUTOPILOT_MAX_TRAILING_LOGS="250"
readonly DEFAULT_AUTOPILOT_SERVER_STABILIZATION_TIME="10s"
readonly DEFAULT_AUTOPILOT_REDUNDANCY_ZONE_TAG="az"
readonly DEFAULT_AUTOPILOT_DISABLE_UPGRADE_MIGRATION="false"

if [[ ! -d "$BASH_COMMONS_DIR" ]]; then
  echo "ERROR: this script requires that bash-commons is installed in $BASH_COMMONS_DIR. See https://github.com/gruntwork-io/bash-commons for more info."
  exit 1
fi

source "$BASH_COMMONS_DIR/assert.sh"
source "$BASH_COMMONS_DIR/log.sh"
source "$BASH_COMMONS_DIR/os.sh"

function print_usage {
  echo
  echo "Usage: run-consul [OPTIONS]"
  echo
  echo "This script is used to configure and run Consul on an Alibaba Cloud ECS Instance."
  echo
  echo "Options:"
  echo
  echo -e "  --server\t\tIf set, run in server mode."
  echo -e "  --client\t\tIf set, run in client mode."
  echo -e "  --consul-token\tThe Consul ACL token to use."
  echo -e "  --cluster-tag-name\tThe tag key for ECS auto-discovery."
  echo -e "  --cluster-tag-value\tThe tag value for ECS auto-discovery."
  echo -e "  --datacenter\t\tThe name of the datacenter Consul is running in. Defaults to ECS region."
  echo -e "  --config-dir\t\tThe path to the Consul config folder."
  echo -e "  --data-dir\t\tThe path to the Consul data folder."
  echo -e "  --systemd-stdout\tThe StandardOutput option of the systemd unit."
  echo -e "  --systemd-stderr\tThe StandardError option of the systemd unit."
  echo -e "  --bin-dir\t\tThe path to the folder with Consul binary."
  echo -e "  --user\t\tThe user to run Consul as."
  echo -e "  --enable-gossip-encryption"
  echo -e "  --gossip-encryption-key"
  echo -e "  --dns-request-token\tThe token to use for DNS requests."
  echo -e "  --enable-rpc-encryption"
  echo -e "  --ca-path"
  echo -e "  --cert-file-path"
  echo -e "  --key-file-path"
  echo -e "  --verify-server-hostname"
  echo -e "  --environment\t\tA single env var KEY=val to pass to Consul. Repeatable."
  echo -e "  --skip-consul-config\tSkip generating the Consul config file."
  echo -e "  --recursor\t\tUpstream DNS recursor. Repeatable."
  echo
  echo "Autopilot options:"
  echo -e "  --autopilot-cleanup-dead-servers\t(default $DEFAULT_AUTOPILOT_CLEANUP_DEAD_SERVERS)"
  echo -e "  --autopilot-last-contact-threshold\t(default $DEFAULT_AUTOPILOT_LAST_CONTACT_THRESHOLD)"
  echo -e "  --autopilot-max-trailing-logs\t\t(default $DEFAULT_AUTOPILOT_MAX_TRAILING_LOGS)"
  echo -e "  --autopilot-server-stabilization-time\t(default $DEFAULT_AUTOPILOT_SERVER_STABILIZATION_TIME)"
  echo -e "  --autopilot-redundancy-zone-tag\t(default $DEFAULT_AUTOPILOT_REDUNDANCY_ZONE_TAG)"
  echo -e "  --autopilot-disable-upgrade-migration"
  echo -e "  --autopilot-upgrade-version-tag"
}

# Get a value from Alibaba Cloud ECS metadata.
function get_instance_metadata_value {
  local -r path="$1"
  log_info "Looking up Metadata value at $ALICLOUD_METADATA_URL/$path"
  curl --silent --show-error --location --fail \
    --connect-timeout 2 --max-time 5 \
    "$ALICLOUD_METADATA_URL/$path" || echo ""
}

# Read the value of an instance tag (Alibaba Cloud exposes them via metadata).
# See https://help.aliyun.com/document_detail/49122.html#title-w8t-cba-77r
function get_instance_tag_value {
  local -r key="$1"
  log_info "Looking up ECS tag value for key \"$key\""
  get_instance_metadata_value "tags/instance/$key"
}

function get_instance_region {
  log_info "Looking up Region of the current ECS Instance"
  get_instance_metadata_value "region-id"
}

function get_instance_zone {
  log_info "Looking up Availability Zone of the current ECS Instance"
  get_instance_metadata_value "zone-id"
}

function get_instance_name {
  log_info "Looking up current ECS Instance ID"
  get_instance_metadata_value "instance-id"
}

function get_instance_ip_address {
  log_info "Looking up ECS Instance IP Address"
  get_instance_metadata_value "private-ipv4"
}

function split_by_lines {
  local prefix="$1"
  shift

  for var in "$@"; do
    echo "${prefix}${var}"
  done
}

function generate_consul_config {
  local -r server="${1}"
  local -r consul_token="${2}"
  local -r config_dir="${3}"
  local -r user="${4}"
  local -r cluster_tag_name="${5}"
  local -r cluster_tag_value="${6}"
  local -r datacenter="${7}"
  local -r enable_gossip_encryption="${8}"
  local -r gossip_encryption_key="${9}"
  local -r enable_rpc_encryption="${10}"
  local -r verify_server_hostname="${11}"
  local -r ca_path="${12}"
  local -r cert_file_path="${13}"
  local -r key_file_path="${14}"
  local -r cleanup_dead_servers="${15}"
  local -r last_contact_threshold="${16}"
  local -r max_trailing_logs="${17}"
  local -r server_stabilization_time="${18}"
  local -r redundancy_zone_tag="${19}"
  local -r disable_upgrade_migration="${20}"
  local -r upgrade_version_tag=${21}
  local -r config_path="$config_dir/$CONSUL_CONFIG_FILE"

  shift 20
  local -ar recursors=("$@")

  local instance_name=""
  local instance_ip_address=""
  local instance_region=""
  local ui="false"

  instance_ip_address=$(get_instance_ip_address)
  instance_name=$(get_instance_name)
  instance_region=$(get_instance_region)

  # AlibabaCloud cloud-auto-join: provider=aliyun + tag_key + tag_value.
  # Credentials obtained automatically from ECS RAM Role via metadata (no access_key in user_data).
  # See https://developer.hashicorp.com/consul/docs/install/cloud-auto-join#alibaba-cloud
  local retry_join_json=""
  if [[ -z "$cluster_tag_name" ]] || [[ -z "$cluster_tag_value" ]]; then
    log_warn "The --cluster-tag-name or --cluster-tag-value property is empty. Will not automatically try to form a cluster based on ECS tags."
  else
    retry_join_json=$(
      cat <<EOF
"retry_join": ["provider=aliyun region=$instance_region tag_key=$cluster_tag_name tag_value=$cluster_tag_value"],
EOF
    )
  fi

  local recursors_config=""
  if [[ ${#recursors[@]} -ne 0 ]]; then
    recursors_config="\"recursors\" : [ "
    for recursor in "${recursors[@]}"; do
      recursors_config="${recursors_config}\"${recursor}\", "
    done
    recursors_config=$(echo "${recursors_config}" | sed 's/, $//')" ],"
  fi

  local bootstrap_expect=""
  if [[ "$server" == "true" ]]; then
    local cluster_size=""

    cluster_size=$(get_instance_tag_value "$CLUSTER_SIZE_INSTANCE_METADATA_KEY_NAME")

    bootstrap_expect="\"bootstrap_expect\": $cluster_size,"
    ui="true"
  fi

  local autopilot_configuration
  autopilot_configuration=$(
    cat <<EOF
"autopilot": {
  "cleanup_dead_servers": $cleanup_dead_servers,
  "last_contact_threshold": "$last_contact_threshold",
  "max_trailing_logs": $max_trailing_logs,
  "server_stabilization_time": "$server_stabilization_time",
  "redundancy_zone_tag": "$redundancy_zone_tag",
  "disable_upgrade_migration": $disable_upgrade_migration,
  "upgrade_version_tag": "$upgrade_version_tag"
},
EOF
  )

  local gossip_encryption_configuration=""
  if [[ "$enable_gossip_encryption" == "true" && -n "$gossip_encryption_key" ]]; then
    log_info "Creating gossip encryption configuration"
    gossip_encryption_configuration="\"encrypt\": \"$gossip_encryption_key\","
  fi

  local rpc_encryption_configuration=""
  if [[ "$enable_rpc_encryption" == "true" && -n "$ca_path" && -n "$cert_file_path" && -n "$key_file_path" ]]; then
    log_info "Creating RPC encryption configuration"
    rpc_encryption_configuration=$(
      cat <<EOF
"verify_outgoing": true,
"verify_incoming": true,
"verify_server_hostname": $verify_server_hostname,
"ca_path": "$ca_path",
"cert_file": "$cert_file_path",
"key_file": "$key_file_path",
EOF
    )
  fi

  log_info "Creating default Consul configuration"
  local default_config_json
  default_config_json=$(
    cat <<EOF
{
  "connect": {
    "enabled": true
  },
  "acl": {
    "enabled": true,
    "default_policy": "deny",
    "enable_token_persistence": true,
    "tokens": {
      "default": "$consul_token"
    }
  },
  "telemetry": {
    "prometheus_retention_time": "2h",
    "disable_hostname": true
  },
  "limits": {
    "http_max_conns_per_client": 80
  },
  "advertise_addr": "$instance_ip_address",
  "bind_addr": "$instance_ip_address",
  $bootstrap_expect
  "client_addr": "0.0.0.0",
  "datacenter": "$datacenter",
  "node_name": "$instance_name",
  "leave_on_terminate": true,
  "skip_leave_on_interrupt": true,
  $recursors_config
  $retry_join_json
  "server": $server,
  $gossip_encryption_configuration
  $rpc_encryption_configuration
  $autopilot_configuration
  "ui": $ui
}
EOF
  )

  log_info "Installing Consul config file in $config_path"
  echo "$default_config_json" | jq '.' >"$config_path"
  chown "$user:$user" "$config_path"
}

function generate_systemd_config {
  local -r systemd_config_path="$1"
  local -r consul_config_dir="$2"
  local -r consul_data_dir="$3"
  local -r consul_systemd_stdout="$4"
  local -r consul_systemd_stderr="$5"
  local -r consul_bin_dir="$6"
  local -r consul_user="$7"
  shift 7
  local -ar environment=("$@")
  local -r config_path="$consul_config_dir/$CONSUL_CONFIG_FILE"

  log_info "Creating systemd config file to run Consul in $systemd_config_path"

  local -r unit_config=$(
    cat <<EOF
[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=$config_path
EOF
  )

  local -r service_config=$(
    cat <<EOF
[Service]
Type=notify
User=$consul_user
Group=$consul_user
ExecStart=$consul_bin_dir/consul agent -config-dir $consul_config_dir -data-dir $consul_data_dir
ExecReload=$consul_bin_dir/consul reload
ExecStop=$consul_bin_dir/consul leave
KillMode=process
Restart=on-failure
TimeoutSec=300s
LimitNOFILE=65536
$(split_by_lines "Environment=" "${environment[@]}")
EOF
  )

  local log_config=""
  if [[ -n $consul_systemd_stdout ]]; then
    log_config+="StandardOutput=$consul_systemd_stdout\n"
  fi
  if [[ -n $consul_systemd_stderr ]]; then
    log_config+="StandardError=$consul_systemd_stderr\n"
  fi

  local -r install_config=$(
    cat <<EOF
[Install]
WantedBy=multi-user.target
EOF
  )

  echo -e "$unit_config" >"$systemd_config_path"
  echo -e "$service_config" >>"$systemd_config_path"
  echo -e "$log_config" >>"$systemd_config_path"
  echo -e "$install_config" >>"$systemd_config_path"
}

function start_consul {
  log_info "Reloading systemd config and starting Consul"

  sudo systemctl daemon-reload
  sudo systemctl enable consul.service
  sudo systemctl restart consul.service
}

function bootstrap {
  log_info "Waiting for Consul to start"
  instance_ip_address=$(get_instance_ip_address)
  log_info "Instance IP Address: $instance_ip_address"

  while true; do
    consul_leader_addr=$(curl http://localhost:8500/v1/status/leader 2>/dev/null || true)
    log_info "Consul leader address: $consul_leader_addr"

    if [[ "$consul_leader_addr" == "\"$instance_ip_address:8300\"" ]]; then
      local consul_token="$1"
      log_info "Bootstrapping Consul"
      echo "${consul_token}" >/tmp/consul.token
      consul acl bootstrap /tmp/consul.token
      rm /tmp/consul.token

      break
    fi

    if [[ -n "$consul_leader_addr" && "$consul_leader_addr" != "\"\"" ]]; then
      log_info "Consul is already bootstrapped"
      break
    fi

    log_info "Waiting for Consul to start"
    sleep 1
  done
}

function setup_dns_resolving {
  local consul_token="$1"
  local dns_request_token="$2"

  until consul info -token="${consul_token}" > /dev/null 2>&1;
  do
    log_info "Waiting for Consul to start"
    sleep 1
  done

  if (($(consul acl policy read -name="dns-request-policy" -token="${consul_token}" -format=json | jq '.ID' | wc -l) > 0)); then
    log_info "DNS Request Policy already exists"
    return
  else
    touch dns-request-policy.hcl
    cat <<EOF >dns-request-policy.hcl
node_prefix "" {
  policy = "read"
}
service_prefix "" {
  policy = "read"
}
EOF

    touch register-service-policy.hcl
    cat <<EOF >register-service-policy.hcl
service_prefix "" {
  policy = "write"
}
EOF
      consul acl policy create -name "dns-request-policy" -rules @dns-request-policy.hcl -token="${consul_token}"
      consul acl policy create -name "register-service-policy" -rules @register-service-policy.hcl -token="${consul_token}"
      consul acl token create -secret "${dns_request_token}" -description "Client Token" -policy-name "dns-request-policy" -policy-name "register-service-policy" -token="${consul_token}"
      rm dns-request-policy.hcl
      rm register-service-policy.hcl
  fi


  consul acl set-agent-token -token="${consul_token}" default "${dns_request_token}"
  log_info "Client token set"
}

function get_owner_of_path {
  local -r path="$1"
  ls -ld "$path" | awk '{print $3}'
}

function get_owner_home_dir {
  local -r user="$1"

  local home_dir=""
  home_dir=$(sudo su - $user -c 'echo $HOME')

  if [[ "$home_dir" == "/" ]]; then
    log_error "No \$HOME directory is set for user $user. This may cause unpredictable behavior with Consul. Exiting."
    exit 1
  fi

  echo "$home_dir"
}

function run {
  local server="false"
  local client="false"
  local config_dir=""
  local data_dir=""
  local systemd_stdout=""
  local systemd_stderr=""
  local bin_dir=""
  local user=""
  local cluster_tag_name=""
  local cluster_tag_value=""
  local datacenter=""
  local upgrade_version_tag=""
  local enable_gossip_encryption="false"
  local gossip_encryption_key=""
  local enable_rpc_encryption="false"
  local verify_server_hostname="false"
  local ca_path=""
  local cert_file_path=""
  local key_file_path=""
  local environment=()
  local skip_consul_config="false"
  local recursors=()
  local cleanup_dead_servers="$DEFAULT_AUTOPILOT_CLEANUP_DEAD_SERVERS"
  local last_contact_threshold="$DEFAULT_AUTOPILOT_LAST_CONTACT_THRESHOLD"
  local max_trailing_logs="$DEFAULT_AUTOPILOT_MAX_TRAILING_LOGS"
  local server_stabilization_time="$DEFAULT_AUTOPILOT_SERVER_STABILIZATION_TIME"
  local redundancy_zone_tag="$DEFAULT_AUTOPILOT_REDUNDANCY_ZONE_TAG"
  local disable_upgrade_migration="$DEFAULT_AUTOPILOT_DISABLE_UPGRADE_MIGRATION"

  while [[ $# -gt 0 ]]; do
    local key="$1"

    case "$key" in
    --server)
      server="true"
      ;;
    --client)
      client="true"
      ;;
    --consul-token)
      assert_not_empty "$key" "$2"
      consul_token="$2"
      shift
      ;;
    --cluster-tag-value)
      assert_not_empty "$key" "$2"
      cluster_tag_value="$2"
      shift
      ;;
    --config-dir)
      assert_not_empty "$key" "$2"
      config_dir="$2"
      shift
      ;;
    --data-dir)
      assert_not_empty "$key" "$2"
      data_dir="$2"
      shift
      ;;
    --systemd-stdout)
      assert_not_empty "$key" "$2"
      systemd_stdout="$2"
      shift
      ;;
    --systemd-stderr)
      assert_not_empty "$key" "$2"
      systemd_stderr="$2"
      shift
      ;;
    --bin-dir)
      assert_not_empty "$key" "$2"
      bin_dir="$2"
      shift
      ;;
    --user)
      assert_not_empty "$key" "$2"
      user="$2"
      shift
      ;;
    --cluster-tag-name)
      assert_not_empty "$key" "$2"
      cluster_tag_name="$2"
      shift
      ;;
    --datacenter)
      assert_not_empty "$key" "$2"
      datacenter="$2"
      shift
      ;;
    --autopilot-cleanup-dead-servers)
      assert_not_empty "$key" "$2"
      cleanup_dead_servers="$2"
      shift
      ;;
    --autopilot-last-contact-threshold)
      assert_not_empty "$key" "$2"
      last_contact_threshold="$2"
      shift
      ;;
    --autopilot-max-trailing-logs)
      assert_not_empty "$key" "$2"
      max_trailing_logs="$2"
      shift
      ;;
    --autopilot-server-stabilization-time)
      assert_not_empty "$key" "$2"
      server_stabilization_time="$2"
      shift
      ;;
    --autopilot-redundancy-zone-tag)
      assert_not_empty "$key" "$2"
      redundancy_zone_tag="$2"
      shift
      ;;
    --autopilot-disable-upgrade-migration)
      disable_upgrade_migration="true"
      shift
      ;;
    --autopilot-upgrade-version-tag)
      assert_not_empty "$key" "$2"
      upgrade_version_tag="$2"
      shift
      ;;
    --enable-gossip-encryption)
      enable_gossip_encryption="true"
      ;;
    --gossip-encryption-key)
      assert_not_empty "$key" "$2"
      gossip_encryption_key="$2"
      shift
      ;;
    --dns-request-token)
      assert_not_empty "$key" "$2"
      dns_request_token="$2"
      shift
      ;;
    --enable-rpc-encryption)
      enable_rpc_encryption="true"
      ;;
    --verify-server-hostname)
      verify_server_hostname="true"
      ;;
    --ca-path)
      assert_not_empty "$key" "$2"
      ca_path="$2"
      shift
      ;;
    --cert-file-path)
      assert_not_empty "$key" "$2"
      cert_file_path="$2"
      shift
      ;;
    --key-file-path)
      assert_not_empty "$key" "$2"
      key_file_path="$2"
      shift
      ;;
    --environment)
      assert_not_empty "$key" "$2"
      environment+=("$2")
      shift
      ;;
    --skip-consul-config)
      skip_consul_config="true"
      ;;
    --recursor)
      assert_not_empty "$key" "$2"
      recursors+=("$2")
      shift
      ;;
    --help)
      print_usage
      exit
      ;;
    *)
      log_error "Unrecognized argument: $key"
      print_usage
      exit 1
      ;;
    esac

    shift
  done

  if [[ ("$server" == "true" && "$client" == "true") || ("$server" == "false" && "$client" == "false") ]]; then
    log_error "Exactly one of --server or --client must be set."
    exit 1
  fi

  assert_is_installed "systemctl"
  assert_is_installed "curl"
  assert_is_installed "jq"

  if [[ -z "$config_dir" ]]; then
    config_dir=$(cd "$SCRIPT_DIR/../config" && pwd)
  fi

  if [[ -z "$data_dir" ]]; then
    data_dir=$(cd "$SCRIPT_DIR/../data" && pwd)
  fi

  if [[ -z "$bin_dir" ]]; then
    bin_dir=$(cd "$SCRIPT_DIR/../bin" && pwd)
  fi

  if [[ -z "$user" ]]; then
    user=$(get_owner_of_path "$config_dir")
  fi

  if [[ -z "$datacenter" ]]; then
    datacenter=$(get_instance_region)
  fi

  if [[ "$skip_consul_config" == "true" ]]; then
    log_info "The --skip-consul-config flag is set, so will not generate a default Consul config file."
  else
    if [[ "$enable_gossip_encryption" == "true" ]]; then
      assert_not_empty "--gossip-encryption-key" "$gossip_encryption_key"
    fi
    if [[ "$enable_rpc_encryption" == "true" ]]; then
      assert_not_empty "--ca-path" "$ca_path"
      assert_not_empty "--cert-file-path" "$cert_file_path"
      assert_not_empty "--key_file_path" "$key_file_path"
    fi

    generate_consul_config "$server" \
      "$consul_token" \
      "$config_dir" \
      "$user" \
      "$cluster_tag_name" \
      "$cluster_tag_value" \
      "$datacenter" \
      "$enable_gossip_encryption" \
      "$gossip_encryption_key" \
      "$enable_rpc_encryption" \
      "$verify_server_hostname" \
      "$ca_path" \
      "$cert_file_path" \
      "$key_file_path" \
      "$cleanup_dead_servers" \
      "$last_contact_threshold" \
      "$max_trailing_logs" \
      "$server_stabilization_time" \
      "$redundancy_zone_tag" \
      "$disable_upgrade_migration" \
      "$upgrade_version_tag" \
      "${recursors[@]}"
  fi

  generate_systemd_config "$SYSTEMD_CONFIG_PATH" "$config_dir" "$data_dir" "$systemd_stdout" "$systemd_stderr" "$bin_dir" "$user" "${environment[@]}"
  start_consul

  if [[ "$client" == "true" ]]; then
    setup_dns_resolving "$consul_token" "$dns_request_token"
  fi

  if [[ "$server" == "true" ]]; then
    bootstrap "$consul_token"
  fi
}

run "$@"
