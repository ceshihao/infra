variable "domain_name" {
  type = string
}

variable "allow_force_destroy" {
  default = false
}

# CAS Certificate ID bound to the ALB HTTPS listener (CAS / Certificate Authority Service).
# On AWS, ACM auto-issues certs; on AlibabaCloud you must apply (acme / manual) and upload to CAS first,
# then pass the cert_id here. When empty, alb.tf still creates the ALB but the HTTPS listener plan
# will fail, prompting the user to provide this value.
variable "alicloud_acm_certificate_id" {
  type        = string
  default     = ""
  description = "CAS Certificate ID bound to the wildcard HTTPS listener; mandatory before terraform apply succeeds"
}

variable "prefix" {
  type        = string
  description = "Name prefix for all resources"
}

variable "bucket_prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "redis_managed" {
  type    = bool
  default = false
}

variable "redis_instance_type" {
  type        = string
  default     = "redis.shard.small.ce"
  description = "AlibabaCloud Tair / Redis Enterprise Edition instance type, e.g. redis.shard.small.ce"
}

variable "redis_replica_size" {
  type    = number
  default = 2
}

variable "api_cluster_size" {
  type    = number
  default = 1
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

variable "client_proxy_env_vars" {
  type      = map(string)
  default   = {}
  sensitive = true
}

variable "orchestrator_env_vars" {
  type      = map(string)
  default   = {}
  sensitive = true
}

variable "template_manager_env_vars" {
  type      = map(string)
  default   = {}
  sensitive = true
}

variable "api_server_machine_type" {
  type        = string
  default     = "ecs.g7.xlarge"
  description = "API server ECS instance type (no nested virtualization required)"
}

variable "api_image_family_prefix" {
  type    = string
  default = ""
}

variable "ingress_count" {
  type    = number
  default = 1
}

variable "client_proxy_count" {
  type    = number
  default = 1
}

variable "clickhouse_cluster_size" {
  type    = number
  default = 1
}

variable "clickhouse_server_machine_type" {
  type    = string
  default = "ecs.g7.xlarge"
}

variable "clickhouse_image_family_prefix" {
  type    = string
  default = ""
}

variable "client_cluster_size" {
  type    = number
  default = 1
}

variable "client_server_machine_type" {
  type        = string
  # Must use ECS Bare Metal instance family; bare metal natively supports KVM/nested virtualization
  # Recommended: ecs.ebmg7.32xlarge / ecs.ebmgn7.* / ecs.ebmc7.*
  default     = "ecs.ebmg7.32xlarge"
  description = "ECS instance type for sandbox client nodes, must support nested virtualization (ECS Bare Metal ebm* family)"
}

variable "client_server_nested_virtualization" {
  type    = bool
  default = true
}

variable "client_node_labels" {
  description = "Labels to assign to client nodes for scheduling purposes"
  type        = list(string)
  default     = []
}

variable "client_image_family_prefix" {
  type    = string
  default = ""
}

variable "control_server_machine_type" {
  type    = string
  default = "ecs.g7.large"
}

variable "control_server_image_family_prefix" {
  type    = string
  default = ""
}

variable "orchestrator_port" {
  type    = number
  default = 5008
}

variable "orchestrator_proxy_port" {
  type    = number
  default = 5007
}

variable "allow_sandbox_internal_cidrs" {
  type        = string
  description = "Comma-separated CIDRs to allow through the sandbox firewall deny list"
  default     = ""
}

variable "envd_timeout" {
  type    = string
  default = "40s"
}

variable "build_cluster_size" {
  type    = number
  default = 1
}

variable "build_server_machine_type" {
  type        = string
  default     = "ecs.ebmg7.32xlarge"
  description = "Build nodes must use ECS Bare Metal (KVM)"
}

variable "build_server_nested_virtualization" {
  type    = bool
  default = true
}

variable "build_node_labels" {
  description = "Labels to assign to build nodes for scheduling purposes"
  type        = list(string)
  default     = []
}

variable "control_server_cluster_size" {
  type    = number
  default = 3
}

variable "traefik_config_files" {
  type        = map(string)
  description = "Map of filename => content for additional Traefik dynamic configuration files"
  default     = {}
}

variable "db_max_open_connections" {
  type    = number
  default = 40
}

variable "db_min_idle_connections" {
  type    = number
  default = 5
}

variable "auth_db_max_open_connections" {
  type    = number
  default = 20
}

variable "auth_db_min_idle_connections" {
  type    = number
  default = 5
}

variable "enable_otel_router_logs" {
  type    = bool
  default = false
}

variable "otel_router_http_port" {
  type    = number
  default = 4321
}

variable "enable_otel_router_metrics" {
  type    = bool
  default = false
}

variable "otel_router_grpc_port" {
  type    = number
  default = 4320
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
