# Core
variable "domain_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "alicloud_region" {
  type = string
}

variable "prefix" {
  type        = string
  description = "Resource name prefix; aligned with init/repositories.tf to derive ACR EE instance name"
}

# Auth
variable "nomad_acl_token" {
  type      = string
  sensitive = true
}

variable "consul_acl_token" {
  type      = string
  sensitive = true
}

# Node pools
variable "api_node_pool" {
  type = string
}

variable "clickhouse_node_pool" {
  type = string
}

variable "clickhouse_jobs_prefix" {
  type = string
}

# Cluster sizes
variable "api_cluster_size" {
  type = number
}

# Ingress
variable "ingress_port" {
  type        = number
  description = "External traffic port number"
}

variable "ingress_internal_port" {
  type        = number
  description = "Internal traffic port number"
}

variable "ingress_count" {
  type = number
}

# Client Proxy
variable "client_proxy_count" {
  type    = number
  default = 1
}

variable "client_proxy_repository_name" {
  type        = string
  description = "ACR repo name for client-proxy image, e.g. core/client-proxy"
}

variable "client_proxy_image_tag" {
  type    = string
  default = "latest"
}

variable "client_proxy_env_vars" {
  type      = map(string)
  default   = {}
  sensitive = true
}

# Redis
variable "redis_managed" {
  type = bool
}

variable "redis_port" {
  type = number
}

# ClickHouse
variable "clickhouse_cluster_size" {
  type = number
}

variable "clickhouse_username" {
  type    = string
  default = "e2b"
}

variable "clickhouse_password" {
  type      = string
  sensitive = true
}

variable "clickhouse_server_secret" {
  type      = string
  sensitive = true
}

variable "clickhouse_port" {
  type    = number
  default = 9000
}

variable "clickhouse_cpu_count" {
  type    = number
  default = 4
}

variable "clickhouse_memory_mb" {
  type    = number
  default = 8192
}

variable "clickhouse_database" {
  type    = string
  default = "default"
}

variable "clickhouse_metrics_port" {
  type    = number
  default = 9363
}

variable "clickhouse_backups_bucket_name" {
  type = string
}

variable "clickhouse_migrator_repository_name" {
  type = string
}

variable "clickhouse_migrator_image_tag" {
  type    = string
  default = "latest"
}

# Grafana / Observability
variable "grafana_otel_collector_token" {
  type      = string
  sensitive = true
}

variable "grafana_otlp_url" {
  type      = string
  sensitive = true
}

variable "grafana_username" {
  type      = string
  sensitive = true
}

# API
variable "api_port" {
  type    = number
  default = 80
}

variable "api_internal_grpc_port" {
  type    = number
  default = 5009
}

variable "api_env_vars" {
  type      = map(string)
  default   = {}
  sensitive = true
}

variable "api_db_migrator_env_vars" {
  type      = map(string)
  default   = {}
  sensitive = true
}

variable "api_memory_mb" {
  type    = number
  default = 512
}

variable "api_cpu_count" {
  type    = number
  default = 1
}

variable "api_repository_name" {
  type        = string
  description = "ACR repo name for api image, e.g. core/api"
}

variable "api_image_tag" {
  type    = string
  default = "latest"
}

variable "db_migrator_repository_name" {
  type = string
}

variable "db_migrator_image_tag" {
  type    = string
  default = "latest"
}

# Orchestrator
variable "orchestrator_node_pool" {
  type = string
}

variable "orchestrator_port" {
  type    = number
  default = 5008
}

variable "orchestrator_proxy_port" {
  type    = number
  default = 5007
}

variable "orchestrator_env_vars" {
  type      = map(string)
  default   = {}
  sensitive = true
}

variable "fc_env_pipeline_bucket_name" {
  type = string
}

variable "template_bucket_name" {
  type = string
}

variable "build_cache_bucket_name" {
  type    = string
  default = ""
}

variable "custom_environments_repository_name" {
  type = string
}

# Template Manager
variable "build_node_pool" {
  type = string
}

variable "template_manager_port" {
  type    = number
  default = 5008
}

variable "template_manager_env_vars" {
  type      = map(string)
  default   = {}
  sensitive = true
}

variable "build_cluster_size" {
  type    = number
  default = 1
}

# Loki
variable "loki_bucket_name" {
  type = string
}

variable "loki_port" {
  type    = number
  default = 3100
}

variable "logs_health_proxy_port" {
  type    = number
  default = 44313
}

# Telemetry
variable "otel_collector_grpc_port" {
  type    = number
  default = 4317
}

variable "logs_proxy_port" {
  type    = number
  default = 30006
}

variable "enable_otel_router_logs" {
  type        = bool
  default     = false
  description = "Enable teeing non-internal customer logs from Vector to otel-router."
}

variable "otel_router_http_port" {
  type        = number
  default     = 4321
  description = "Local otel-router Vector-compatible logs port used by Vector when otel-router log teeing is enabled."
}

variable "enable_otel_router_metrics" {
  type        = bool
  default     = false
  description = "Enable teeing external customer metrics from otel-collector to otel-router."
}

variable "otel_router_grpc_port" {
  type        = number
  default     = 4320
  description = "Local otel-router OTLP gRPC port used by otel-collector when otel-router metric teeing is enabled."
}

# Feature flags
variable "launch_darkly_api_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "traefik_config_files" {
  type = map(string)
}

# Dashboard API
variable "dashboard_api_count" {
  type    = number
  default = 0
}

variable "dashboard_api_env_vars" {
  type      = map(string)
  default   = {}
  sensitive = true
}

variable "dashboard_api_repository_name" {
  type        = string
  default     = ""
  description = "ACR repo name for dashboard-api image, e.g. core/dashboard-api"
}

variable "dashboard_api_image_tag" {
  type    = string
  default = "latest"
}

# Docker Reverse Proxy
variable "docker_reverse_proxy_port" {
  type = object({
    name        = string
    port        = number
    health_path = string
  })
  default = {
    name        = "docker-reverse-proxy"
    port        = 5000
    health_path = "/health"
  }
}

variable "docker_reverse_proxy_env_vars" {
  type      = map(string)
  default   = {}
  sensitive = true
}

variable "docker_reverse_proxy_repository_name" {
  type        = string
  default     = ""
  description = "ACR repo name for docker-reverse-proxy image, e.g. core/docker-reverse-proxy"
}

variable "docker_reverse_proxy_image_tag" {
  type    = string
  default = "latest"
}
