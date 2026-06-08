locals {
  clickhouse_connection_string = var.clickhouse_cluster_size > 0 ? "clickhouse://${var.clickhouse_username}:${var.clickhouse_password}@clickhouse.service.consul:${var.clickhouse_port}/${var.clickhouse_database}" : ""

  # ACR EE VPC domain (consistent with alicloud_acr_account_repository_domain in nomad-cluster/main.tf).
  # AlibabaCloud has no equivalent of data.aws_ecr_image to auto-resolve image_uri from repo+tag,
  # nor does it expose a stable digest data source; we compose the string by convention here.
  acr_domain = "${var.prefix}core-registry-vpc.${var.alicloud_region}.cr.aliyuncs.com"

  api_image_uri                 = "${local.acr_domain}/${var.api_repository_name}:${var.api_image_tag}"
  db_migrator_image_uri         = "${local.acr_domain}/${var.db_migrator_repository_name}:${var.db_migrator_image_tag}"
  client_proxy_image_uri        = "${local.acr_domain}/${var.client_proxy_repository_name}:${var.client_proxy_image_tag}"
  clickhouse_migrator_image_uri = "${local.acr_domain}/${var.clickhouse_migrator_repository_name}:${var.clickhouse_migrator_image_tag}"
  dashboard_api_image_uri       = var.dashboard_api_repository_name != "" ? "${local.acr_domain}/${var.dashboard_api_repository_name}:${var.dashboard_api_image_tag}" : ""
  docker_reverse_proxy_image_uri = var.docker_reverse_proxy_repository_name != "" ? "${local.acr_domain}/${var.docker_reverse_proxy_repository_name}:${var.docker_reverse_proxy_image_tag}" : ""

  docker_reverse_proxy_env_vars = {
    for key, value in var.docker_reverse_proxy_env_vars : key => trimspace(value)
    if value != null && try(trimspace(value), "") != ""
  }
}

# Nomad scheduler config identical to AWS
resource "nomad_scheduler_config" "config" {
  memory_oversubscription_enabled = true
}

module "otel_collector" {
  source = "../../modules/job-otel-collector"

  provider_name = "alicloud"

  otel_collector_grpc_port = var.otel_collector_grpc_port

  grafana_otel_collector_token = var.grafana_otel_collector_token
  grafana_otlp_url             = var.grafana_otlp_url
  grafana_username             = var.grafana_username
  consul_token                 = var.consul_acl_token

  enable_otel_router_metrics = var.enable_otel_router_metrics
  otel_router_grpc_port      = var.otel_router_grpc_port

  clickhouse_username = var.clickhouse_username
  clickhouse_password = var.clickhouse_password
  clickhouse_port     = var.clickhouse_port
  clickhouse_database = var.clickhouse_database
}

module "otel_collector_nomad_server" {
  source = "../../modules/job-otel-collector-nomad-server"

  provider_name = "alicloud"
  node_pool     = var.api_node_pool

  grafana_otel_collector_token = var.grafana_otel_collector_token
  grafana_otlp_url             = var.grafana_otlp_url
  grafana_username             = var.grafana_username
}

module "redis" {
  source = "../../modules/job-redis"
  count  = var.redis_managed ? 0 : 1

  node_pool   = var.api_node_pool
  port_number = var.redis_port
  port_name   = "redis"
}

module "ingress" {
  source = "../../modules/job-ingress"

  ingress_count         = var.ingress_count
  ingress_port          = var.ingress_port
  ingress_internal_port = var.ingress_internal_port

  traefik_config_files = var.traefik_config_files

  node_pool     = var.api_node_pool
  update_stanza = var.api_cluster_size > 1

  nomad_token  = var.nomad_acl_token
  consul_token = var.consul_acl_token

  otel_collector_grpc_endpoint = "localhost:${var.otel_collector_grpc_port}"
}

module "client_proxy" {
  source = "../../modules/job-client-proxy"

  update_stanza      = var.api_cluster_size > 1
  client_proxy_count = var.client_proxy_count

  node_pool = var.api_node_pool

  image        = local.client_proxy_image_uri
  job_env_vars = var.client_proxy_env_vars
}

module "api" {
  source = "../../modules/job-api"

  update_stanza      = var.api_cluster_size > 1
  node_pool          = var.api_node_pool
  prevent_colocation = var.api_cluster_size > 2
  count_instances    = var.api_cluster_size

  memory_mb = var.api_memory_mb
  cpu_count = var.api_cpu_count

  port_name                = "api"
  port_number              = var.api_port
  api_internal_grpc_port   = var.api_internal_grpc_port
  api_docker_image         = local.api_image_uri
  db_migrator_docker_image = local.db_migrator_image_uri
  job_env_vars             = var.api_env_vars
  db_migrator_env_vars     = var.api_db_migrator_env_vars
}

module "dashboard_api" {
  source = "../../modules/job-dashboard-api"
  count  = var.dashboard_api_count > 0 ? 1 : 0

  count_instances = var.dashboard_api_count
  node_pool       = var.api_node_pool
  update_stanza   = var.dashboard_api_count > 1

  image = local.dashboard_api_image_uri

  job_env_vars = var.dashboard_api_env_vars
}

# AWS aws_s3_object -> alicloud_oss_bucket_object data source.
# OSS object etag field serves as an artifact change marker, equivalent to AWS s3 etag.
data "alicloud_oss_bucket_objects" "orchestrator" {
  bucket_name = var.fc_env_pipeline_bucket_name
  key_prefix  = "orchestrator"
}

locals {
  orchestrator_object        = [for o in data.alicloud_oss_bucket_objects.orchestrator.objects : o if o.key == "orchestrator"][0]
  orchestrator_artifact_etag = local.orchestrator_object.etag
  # Nomad artifact stanza supports go-getter style URLs.
  # OSS HTTPS endpoint:  https://<bucket>.oss-<region>.aliyuncs.com/<key>
  orchestrator_artifact_source = "https://${var.fc_env_pipeline_bucket_name}.oss-${var.alicloud_region}.aliyuncs.com/orchestrator?etag=${local.orchestrator_artifact_etag}"
}

module "orchestrator" {
  source = "../../modules/job-orchestrator"

  node_pool  = var.orchestrator_node_pool
  port       = var.orchestrator_port
  proxy_port = var.orchestrator_proxy_port

  environment           = var.environment
  artifact_source       = local.orchestrator_artifact_source
  orchestrator_checksum = local.orchestrator_artifact_etag
  job_env_vars          = var.orchestrator_env_vars
}

data "alicloud_oss_bucket_objects" "template_manager" {
  bucket_name = var.fc_env_pipeline_bucket_name
  key_prefix  = "template-manager"
}

locals {
  template_manager_object        = [for o in data.alicloud_oss_bucket_objects.template_manager.objects : o if o.key == "template-manager"][0]
  template_manager_artifact_etag = local.template_manager_object.etag
  template_manager_artifact_source = "https://${var.fc_env_pipeline_bucket_name}.oss-${var.alicloud_region}.aliyuncs.com/template-manager?etag=${local.template_manager_artifact_etag}"
}

module "template_manager" {
  source = "../../modules/job-template-manager"

  update_stanza = var.build_cluster_size > 1
  node_pool     = var.build_node_pool

  port = var.template_manager_port

  artifact_source = local.template_manager_artifact_source
  job_env_vars    = var.template_manager_env_vars

  nomad_addr  = "https://nomad.${var.domain_name}"
  nomad_token = var.nomad_acl_token
}

data "alicloud_oss_bucket_objects" "nomad_nodepool_apm" {
  count       = var.build_cluster_size > 1 ? 1 : 0
  bucket_name = var.fc_env_pipeline_bucket_name
  key_prefix  = "nomad-nodepool-apm"
}

locals {
  nomad_nodepool_apm_object_etag = (
    var.build_cluster_size > 1
    ? [for o in data.alicloud_oss_bucket_objects.nomad_nodepool_apm[0].objects : o if o.key == "nomad-nodepool-apm"][0].etag
    : ""
  )
}

module "template_manager_autoscaler" {
  source = "../../modules/job-template-manager-autoscaler"
  count  = var.build_cluster_size > 1 ? 1 : 0

  node_pool                  = var.api_node_pool
  nomad_token                = var.nomad_acl_token
  apm_plugin_artifact_source = "https://${var.fc_env_pipeline_bucket_name}.oss-${var.alicloud_region}.aliyuncs.com/nomad-nodepool-apm?etag=${local.nomad_nodepool_apm_object_etag}"
}

# ---
# Loki
# ---
# OSS is accessed via S3-compatible protocol; internal endpoint injected by the alicloud branch in loki.yml.
module "loki" {
  source = "../../modules/job-loki"

  provider_name = "alicloud"
  aws_region    = var.alicloud_region

  node_pool          = var.api_node_pool
  prevent_colocation = var.api_cluster_size > 2
  bucket_name        = var.loki_bucket_name
  loki_port          = var.loki_port
}

# ---
# Logs Collector
# ---
module "logs_collector" {
  source = "../../modules/job-logs-collector"

  loki_endpoint = "http://loki.service.consul:${var.loki_port}"

  enable_otel_router_logs = var.enable_otel_router_logs
  otel_router_http_port   = var.otel_router_http_port

  vector_health_port = var.logs_health_proxy_port
  vector_api_port    = var.logs_proxy_port
}

# ---
# ClickHouse
# ---
module "clickhouse" {
  source = "../../modules/job-clickhouse"

  provider_name = "alicloud"

  node_pool             = var.clickhouse_node_pool
  job_constraint_prefix = var.clickhouse_jobs_prefix
  server_count          = var.clickhouse_cluster_size

  server_secret = var.clickhouse_server_secret

  cpu_count = var.clickhouse_cpu_count
  memory_mb = var.clickhouse_memory_mb

  clickhouse_database = var.clickhouse_database
  clickhouse_username = var.clickhouse_username
  clickhouse_password = var.clickhouse_password
  clickhouse_port     = var.clickhouse_port

  clickhouse_metrics_port = var.clickhouse_metrics_port
  otel_exporter_endpoint  = "http://localhost:${var.otel_collector_grpc_port}"

  aws_region    = var.alicloud_region
  backup_bucket = var.clickhouse_backups_bucket_name

  clickhouse_migrator_image = local.clickhouse_migrator_image_uri
}

# ---
# Docker Reverse Proxy
# ---
resource "nomad_job" "docker_reverse_proxy" {
  jobspec = templatefile("${path.module}/jobs/docker-reverse-proxy.hcl", {
    node_pool         = var.api_node_pool
    image_name        = local.docker_reverse_proxy_image_uri
    port_number       = var.docker_reverse_proxy_port.port
    port_name         = var.docker_reverse_proxy_port.name
    health_check_path = var.docker_reverse_proxy_port.health_path
    job_env_vars      = local.docker_reverse_proxy_env_vars
  })
}
