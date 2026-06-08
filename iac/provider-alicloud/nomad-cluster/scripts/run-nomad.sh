#!/bin/bash
# Configure and start Nomad on an Alibaba Cloud ECS instance.
# Mirrors iac/provider-aws/nomad-cluster/scripts/run-nomad.sh.
#
# Key differences (vs AWS):
#   1. metadata service: 169.254.169.254 + IMDSv2 -> 100.100.100.200 (no token)
#                        region/zone/instance-id/private-ipv4 each have their own path
#                        tags via 100.100.100.200/latest/meta-data/tags/instance/<key>
#   2. firecracker driver: only enabled on bare-metal (ebmg/ebmgn) or nested-virt instances;
#                          other types have client node user_data fail-fast check.
#   3. credentials via ECS RAM Role (metadata 100.100.100.200/latest/meta-data/Ram/security-credentials/<role>);
#      ECR docker login handled by acr-credential-helper on demand during docker pull.

set -e

readonly NOMAD_CONFIG_FILE="default.hcl"
readonly SUPERVISOR_CONFIG_PATH="/etc/supervisor/conf.d/run-nomad.conf"

readonly ALICLOUD_METADATA_URL="http://100.100.100.200/latest/meta-data"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

function print_usage {
  echo
  echo "Usage: run-nomad [OPTIONS]"
  echo
  echo "This script is used to configure and run Nomad on an Alibaba Cloud ECS Instance."
  echo
  echo "Options:"
  echo
  echo -e "  --server\t\tIf set, run in server mode."
  echo -e "  --client\t\tIf set, run in client mode."
  echo -e "  --num-servers\tNumber of servers in the Nomad cluster (required with --server)."
  echo -e "  --consul-token\tThe ACL token that Consul uses."
  echo -e "  --nomad-token\tThe Nomad ACL token."
  echo -e "  --config-dir\tThe path to the Nomad config folder."
  echo -e "  --data-dir\tThe path to the Nomad data folder."
  echo -e "  --bin-dir\tThe path to the folder with Nomad binary."
  echo -e "  --log-dir\tThe path to the Nomad log folder."
  echo -e "  --user\tThe user to run Nomad as."
  echo -e "  --use-sudo\tIf set, run the Nomad agent with sudo."
  echo -e "  --skip-nomad-config\tSkip generating the Nomad config file."
  echo -e "  --node-pool\tWhich node-pool to register the Nomad client into."
  echo -e "  --node-labels\tComma-separated scheduling labels for this node."
  echo
  echo "Example:"
  echo "  run-nomad.sh --server --config-dir /custom/path/to/nomad/config"
}

function log {
  local -r level="$1"
  local -r message="$2"
  local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo >&2 -e "${timestamp} [${level}] [$SCRIPT_NAME] ${message}"
}

function log_info {
  local -r message="$1"
  log "INFO" "$message"
}

function log_warn {
  local -r message="$1"
  log "WARN" "$message"
}

function log_error {
  local -r message="$1"
  log "ERROR" "$message"
}

function strip_prefix {
  local -r str="$1"
  local -r prefix="$2"
  echo "${str#$prefix}"
}

function assert_not_empty {
  local -r arg_name="$1"
  local -r arg_value="$2"

  if [[ -z "$arg_value" ]]; then
    log_error "The value for '$arg_name' cannot be empty"
    print_usage
    exit 1
  fi
}

# Get a value from Alibaba Cloud ECS metadata.
function get_instance_metadata_value {
  local -r path="$1"
  log_info "Looking up Metadata value at $ALICLOUD_METADATA_URL/$path"
  local response_body=""
  if response_body=$(curl --silent --show-error --location --fail \
    --connect-timeout 2 --max-time 5 \
    "$ALICLOUD_METADATA_URL/$path"); then
    echo "$response_body"
  else
    echo ""
  fi
}

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

function assert_is_installed {
  local -r name="$1"

  if [[ ! $(command -v ${name}) ]]; then
    log_error "The binary '$name' is required by this script but is not installed or in the system's PATH."
    exit 1
  fi
}

function generate_nomad_config {
  local -r server="$1"
  local -r client="$2"
  local -r num_servers="$3"
  local -r config_dir="$4"
  local -r user="$5"
  local -r consul_token="$6"
  local -r node_pool="$7"
  local -r node_labels="$8"
  local -r config_path="$config_dir/$NOMAD_CONFIG_FILE"

  local instance_name=""
  local instance_ip_address=""
  local instance_region=""
  local zone=""
  local job_constraint=""

  instance_name=$(get_instance_name)
  instance_ip_address=$(get_instance_ip_address)
  instance_region=$(get_instance_region)
  zone=$(get_instance_zone)
  job_constraint=$(get_instance_tag_value "job-constraint" || true)

  local server_config=""
  if [[ "$server" == "true" ]]; then
    server_config=$(
      cat <<EOF
server {
  enabled = true
  bootstrap_expect = $num_servers
  heartbeat_grace = "1m"

  default_scheduler_config {
    memory_oversubscription_enabled = true
  }
}

EOF
    )
  fi

  local client_config=""
  if [[ "$client" == "true" ]]; then
    client_config=$(
      cat <<EOF
client {
  enabled = true
  node_pool = "$node_pool"
  meta {
    "node_pool" = "$node_pool"
    "node_labels" = "${node_labels:-}"
    ${job_constraint:+"\"job_constraint\"" = "\"$job_constraint\""}
  }
  max_kill_timeout = "24h"
}

plugin "raw_exec" {
  config {
    enabled = true
  }
}

EOF
    )
  fi

  log_info "Creating default Nomad config file in $config_path"
  cat >"$config_path" <<EOF
datacenter = "$zone"
name       = "$instance_name"
region     = "$instance_region"
bind_addr  = "0.0.0.0"

advertise {
  http = "$instance_ip_address"
  rpc  = "$instance_ip_address"
  serf = "$instance_ip_address"
}

leave_on_interrupt = true
leave_on_terminate = true

$client_config

$server_config

plugin_dir = "/opt/nomad/plugins"

plugin "docker" {
  config {
    volumes {
      enabled = true
    }
    auth {
      config = "/root/docker/config.json"
    }
  }
}

log_level = "INFO"
log_json = true

telemetry {
  collection_interval = "5s"
  disable_hostname = true
  prometheus_metrics = true
  publish_allocation_metrics = true
  publish_node_metrics = true
}

acl {
  enabled = true
}

limits {
  http_max_conns_per_client = 80
  rpc_max_conns_per_client = 80
}

consul {
  address = "127.0.0.1:8500"
  allow_unauthenticated = false
  token = "$consul_token"
}
EOF
  chown "$user:$user" "$config_path"
}

function generate_supervisor_config {
  local -r supervisor_config_path="$1"
  local -r nomad_config_dir="$2"
  local -r nomad_data_dir="$3"
  local -r nomad_bin_dir="$4"
  local -r nomad_log_dir="$5"
  local nomad_user="$6"
  local -r use_sudo="$7"

  if [[ "$use_sudo" == "true" ]]; then
    log_info "The --use-sudo flag is set, so running Nomad as the root user"
    nomad_user="root"
  fi

  log_info "Creating Supervisor config file to run Nomad in $supervisor_config_path"
  cat >"$supervisor_config_path" <<EOF
[program:nomad]
command=$nomad_bin_dir/nomad agent -config $nomad_config_dir -data-dir $nomad_data_dir
stdout_logfile=$nomad_log_dir/nomad-stdout.log
stderr_logfile=$nomad_log_dir/nomad-error.log
numprocs=1
autostart=true
autorestart=true
stopsignal=INT
minfds=65536
user=$nomad_user
EOF
}

function start_nomad {
  log_info "Reloading Supervisor config and starting Nomad"
  supervisorctl reread
  supervisorctl update
}

function bootstrap {
  log_info "Waiting for Nomad to start"
  while test -z "$(curl -s http://127.0.0.1:4646/v1/agent/health)"; do
    log_info "Nomad not yet started. Waiting for 1 second."
    sleep 1
  done
  log_info "Nomad server started."

  local -r nomad_token="$1"
  log_info "Bootstrapping Nomad"
  echo "$nomad_token" >"/tmp/nomad.token"
  nomad acl bootstrap /tmp/nomad.token
  rm "/tmp/nomad.token"
}

function create_node_pools {
  local -r nomad_token="$1"
  log_info "Creating node pools"
  cat > "$config_dir/api_node_pool.hcl"  <<EOF
node_pool "api" {
  description = "Nodes for api."
}
EOF
  nomad node pool apply -token "$nomad_token" "$config_dir/api_node_pool.hcl"
  cat > "$config_dir/build_node_pool.hcl"  <<EOF
node_pool "build" {
  description = "Nodes for template builds."
}
EOF
  nomad node pool apply -token "$nomad_token" "$config_dir/build_node_pool.hcl"
}

function get_owner_of_path {
  local -r path="$1"
  ls -ld "$path" | awk '{print $3}'
}

function run {
  local server="false"
  local client="false"
  local num_servers=""
  local all_args=()

  while [[ $# > 0 ]]; do
    local key="$1"

    case "$key" in
    --server)
      server="true"
      ;;
    --client)
      client="true"
      ;;
    --num-servers)
      num_servers="$2"
      shift
      ;;
    --nomad-token)
      assert_not_empty "$key" "$2"
      nomad_token="$2"
      shift
      ;;
    --consul-token)
      assert_not_empty "$key" "$2"
      consul_token="$2"
      shift
      ;;
    --node-pool)
      node_pool="$2"
      shift
      ;;
    --node-labels)
      node_labels="$2"
      shift
      ;;
    --cluster-tag-value)
      assert_not_empty "$key" "$2"
      cluster_tag_value="$2"
      shift
      ;;
    --use-sudo)
      use_sudo="true"
      ;;
    *)
      log_error "Unrecognized argument: $key"
      print_usage
      exit 1
      ;;
    esac

    shift
  done

  if [[ "$server" == "true" ]]; then
    assert_not_empty "--num-servers" "$num_servers"
  fi

  if [[ "$server" == "false" && "$client" == "false" ]]; then
    log_error "At least one of --server or --client must be set"
    exit 1
  fi

  if [[ -z "$use_sudo" ]]; then
    if [[ "$client" == "true" ]]; then
      use_sudo="true"
    else
      use_sudo="false"
    fi
  fi

  assert_is_installed "supervisorctl"
  assert_is_installed "curl"

  config_dir=$(cd "$SCRIPT_DIR/../config" && pwd)

  data_dir=$(cd "$SCRIPT_DIR/../data" && pwd)

  bin_dir=$(cd "$SCRIPT_DIR/../bin" && pwd)

  log_dir=$(cd "$SCRIPT_DIR/../log" && pwd)

  user=$(get_owner_of_path "$config_dir")

  generate_nomad_config "$server" "$client" "$num_servers" "$config_dir" "$user" "$consul_token" "$node_pool" "$node_labels"
  generate_supervisor_config "$SUPERVISOR_CONFIG_PATH" "$config_dir" "$data_dir" "$bin_dir" "$log_dir" "$user" "$use_sudo"
  start_nomad

  if [[ "$server" == "true" ]]; then
    bootstrap "$nomad_token"
    create_node_pools "$nomad_token"
  fi
}

run "$@"
