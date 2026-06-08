# ============================================================================
# OSS Bucket outputs
# ============================================================================
output "setup_bucket_name" {
  value = alicloud_oss_bucket.setup.bucket
}

output "fc_template_build_cache_bucket_name" {
  value = alicloud_oss_bucket.fc_template_build_cache.bucket
}

output "fc_template_bucket_name" {
  value = alicloud_oss_bucket.fc_templates.bucket
}

output "fc_env_pipeline_bucket_name" {
  value = alicloud_oss_bucket.fc_env_pipeline.bucket
}

output "fc_kernels_bucket_name" {
  value = alicloud_oss_bucket.fc_kernels.bucket
}

output "fc_versions_bucket_name" {
  value = alicloud_oss_bucket.fc_versions.bucket
}

output "fc_busybox_bucket_name" {
  value = alicloud_oss_bucket.fc_busybox.bucket
}

output "load_balancer_logs_bucket_name" {
  value = alicloud_oss_bucket.load_balancer_logs.bucket
}

output "loki_bucket_name" {
  value = alicloud_oss_bucket.loki_storage.bucket
}

output "clickhouse_backups_bucket_name" {
  value = alicloud_oss_bucket.clickhouse_backups.bucket
}

# ============================================================================
# ACR outputs
# ============================================================================
output "acr_instance_id" {
  value = alicloud_cr_ee_instance.core.id
}

output "acr_namespace" {
  value = alicloud_cr_ee_namespace.core.name
}

# Output full namespace/repo path for composing ACR EE VPC URL:
#   <instance_name>-registry-vpc.<region>.cr.aliyuncs.com/<namespace>/<repo>:<tag>
# Equivalent to AWS ECR repository name `${prefix}core/<service>` in URL literal form.
output "client_proxy_repository_name" {
  value = "${alicloud_cr_ee_namespace.core.name}/${alicloud_cr_ee_repo.client_proxy.name}"
}

output "clickhouse_migrator_repository_name" {
  value = "${alicloud_cr_ee_namespace.core.name}/${alicloud_cr_ee_repo.clickhouse_migrator.name}"
}

output "custom_environments_repository_name" {
  value = "${alicloud_cr_ee_namespace.core.name}/${alicloud_cr_ee_repo.custom_environments.name}"
}

output "api_repository_name" {
  value = "${alicloud_cr_ee_namespace.core.name}/${alicloud_cr_ee_repo.api.name}"
}

output "db_migrator_repository_name" {
  value = "${alicloud_cr_ee_namespace.core.name}/${alicloud_cr_ee_repo.db_migrator.name}"
}

output "dashboard_api_repository_name" {
  value = "${alicloud_cr_ee_namespace.core.name}/${alicloud_cr_ee_repo.dashboard_api.name}"
}

output "docker_reverse_proxy_repository_name" {
  value = "${alicloud_cr_ee_namespace.core.name}/${alicloud_cr_ee_repo.docker_reverse_proxy.name}"
}

# ACR EE VPC image registry domain: provided directly to parent modules to avoid repeated concatenation
output "acr_vpc_endpoint" {
  value = "${alicloud_cr_ee_instance.core.instance_name}-registry-vpc"
}

# ============================================================================
# Cloudflare
# ============================================================================
output "cloudflare" {
  value = module.cloudflare.cloudflare
}

# ============================================================================
# Network
# ============================================================================
output "vpc_id" {
  value = module.network.vpc_id
}

output "vpc_public_subnet_ids" {
  value = module.network.vpc_public_subnet_ids
}

output "vpc_private_subnet_ids" {
  value = module.network.vpc_private_subnet_ids
}
