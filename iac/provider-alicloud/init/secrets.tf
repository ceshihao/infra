# ----------------------------------------------------------------------------
# Secrets — using AlibabaCloud KMS Secrets Manager (data_key_secret)
# Mirrors the 9 secrets + 1 cluster secret in provider-aws/init/secrets.tf.
#
# Notes:
#   - alicloud_kms_secret defaults to secret_data_type = "text"; use jsonencode manually for JSON
#   - encryption_key_id can be omitted; defaults to AlibabaCloud managed key (alias/acs/kms)
#   - lifecycle ignore_changes = [secret_data] is equivalent to AWS ignore_changes = [secret_string]:
#     first apply writes random/placeholder values; ops manually updates later in the KMS console
# ----------------------------------------------------------------------------

# ---
# Clickhouse
# ---
resource "random_string" "clickhouse_password" {
  length  = 32
  special = false
}

resource "random_string" "clickhouse_server_secret" {
  length  = 32
  special = false
}

resource "alicloud_kms_secret" "clickhouse" {
  secret_name                = "${var.prefix}clickhouse"
  secret_data_type           = "text"
  version_id                 = "v1"
  force_delete_without_recovery = var.allow_force_destroy

  secret_data = jsonencode({
    "CLICKHOUSE_USERNAME" = "e2b",
    "CLICKHOUSE_PASSWORD" = random_string.clickhouse_password.result,
    "SERVER_SECRET"       = random_string.clickhouse_server_secret.result,
  })

  lifecycle {
    ignore_changes = [secret_data]
  }
}

data "alicloud_kms_secret" "clickhouse" {
  secret_name = alicloud_kms_secret.clickhouse.secret_name
  depends_on  = [alicloud_kms_secret.clickhouse]
}

locals {
  clickhouse_raw = jsondecode(data.alicloud_kms_secret.clickhouse.secret_data)
}

output "clickhouse" {
  value = {
    username      = local.clickhouse_raw["CLICKHOUSE_USERNAME"]
    password      = local.clickhouse_raw["CLICKHOUSE_PASSWORD"]
    server_secret = local.clickhouse_raw["SERVER_SECRET"]
  }
  sensitive = true
}

# ---
# Grafana
# ---
resource "alicloud_kms_secret" "grafana" {
  secret_name                = "${var.prefix}grafana"
  secret_data_type           = "text"
  version_id                 = "v1"
  force_delete_without_recovery = var.allow_force_destroy

  secret_data = jsonencode({
    "API_KEY"                  = " ",
    "OTLP_URL"                 = " ",
    "OTEL_COLLECTOR_TOKEN"     = " ",
    "USERNAME"                 = " ",
    "LOGS_USER"                = " ",
    "LOGS_URL"                 = " ",
    "LOGS_COLLECTOR_API_TOKEN" = " ",
  })

  lifecycle {
    ignore_changes = [secret_data]
  }
}

data "alicloud_kms_secret" "grafana" {
  secret_name = alicloud_kms_secret.grafana.secret_name
  depends_on  = [alicloud_kms_secret.grafana]
}

locals {
  grafana_raw = jsondecode(data.alicloud_kms_secret.grafana.secret_data)
}

output "grafana" {
  value = {
    api_key              = local.grafana_raw["API_KEY"]
    otlp_url             = local.grafana_raw["OTLP_URL"]
    otel_collector_token = local.grafana_raw["OTEL_COLLECTOR_TOKEN"]
    username             = local.grafana_raw["USERNAME"]
  }
  sensitive = true
}

# ---
# API Secret
# ---
resource "random_string" "api_secret" {
  length  = 32
  special = false
}

resource "alicloud_kms_secret" "api_secret" {
  secret_name                = "${var.prefix}api-secret"
  secret_data_type           = "text"
  version_id                 = "v1"
  secret_data                = random_string.api_secret.result
  force_delete_without_recovery = var.allow_force_destroy

  lifecycle {
    ignore_changes = [secret_data]
  }
}

data "alicloud_kms_secret" "api_secret" {
  secret_name = alicloud_kms_secret.api_secret.secret_name
  depends_on  = [alicloud_kms_secret.api_secret]
}

output "api_secret" {
  value     = data.alicloud_kms_secret.api_secret.secret_data
  sensitive = true
}

# ---
# Launch Darkly
# ---
resource "alicloud_kms_secret" "launch_darkly_api_key" {
  secret_name                = "${var.prefix}launch-darkly-api-key"
  secret_data_type           = "text"
  version_id                 = "v1"
  secret_data                = " "
  force_delete_without_recovery = var.allow_force_destroy

  lifecycle {
    ignore_changes = [secret_data]
  }
}

data "alicloud_kms_secret" "launch_darkly_api_key" {
  secret_name = alicloud_kms_secret.launch_darkly_api_key.secret_name
  depends_on  = [alicloud_kms_secret.launch_darkly_api_key]
}

output "launch_darkly_api_key" {
  value     = data.alicloud_kms_secret.launch_darkly_api_key.secret_data
  sensitive = true
}

# ---
# PostgreSQL connection string
# ---
resource "alicloud_kms_secret" "postgres_connection_string" {
  secret_name                = "${var.prefix}postgres-connection-string"
  secret_data_type           = "text"
  version_id                 = "v1"
  secret_data                = " "
  force_delete_without_recovery = var.allow_force_destroy

  lifecycle {
    ignore_changes = [secret_data]
  }
}

data "alicloud_kms_secret" "postgres_connection_string" {
  secret_name = alicloud_kms_secret.postgres_connection_string.secret_name
  depends_on  = [alicloud_kms_secret.postgres_connection_string]
}

output "postgres_connection_string_secret_name" {
  value = alicloud_kms_secret.postgres_connection_string.secret_name
}

output "postgres_connection_string" {
  value     = data.alicloud_kms_secret.postgres_connection_string.secret_data
  sensitive = true
}

# ---
# Supabase JWT secrets
# ---
resource "alicloud_kms_secret" "supabase_jwt_secrets" {
  secret_name                = "${var.prefix}supabase-jwt-secrets"
  secret_data_type           = "text"
  version_id                 = "v1"
  secret_data                = " "
  force_delete_without_recovery = var.allow_force_destroy

  lifecycle {
    ignore_changes = [secret_data]
  }
}

data "alicloud_kms_secret" "supabase_jwt_secrets" {
  secret_name = alicloud_kms_secret.supabase_jwt_secrets.secret_name
  depends_on  = [alicloud_kms_secret.supabase_jwt_secrets]
}

output "supabase_jwt_secret_name" {
  value = alicloud_kms_secret.supabase_jwt_secrets.secret_name
}

output "supabase_jwt_secrets" {
  value     = data.alicloud_kms_secret.supabase_jwt_secrets.secret_data
  sensitive = true
}

# ---
# Admin token
# ---
resource "random_string" "admin_token" {
  length  = 32
  special = false
}

resource "alicloud_kms_secret" "admin_token" {
  secret_name                = "${var.prefix}admin-token"
  secret_data_type           = "text"
  version_id                 = "v1"
  secret_data                = random_string.admin_token.result
  force_delete_without_recovery = var.allow_force_destroy

  lifecycle {
    ignore_changes = [secret_data]
  }
}

data "alicloud_kms_secret" "admin_token" {
  secret_name = alicloud_kms_secret.admin_token.secret_name
  depends_on  = [alicloud_kms_secret.admin_token]
}

output "admin_token" {
  value     = data.alicloud_kms_secret.admin_token.secret_data
  sensitive = true
}

# ---
# Sandbox access token hash seed
# ---
resource "random_string" "sandbox_access_token_hash_seed" {
  length  = 32
  special = false
}

resource "alicloud_kms_secret" "sandbox_access_token_hash_seed" {
  secret_name                = "${var.prefix}sandbox-access-token-hash-seed"
  secret_data_type           = "text"
  version_id                 = "v1"
  secret_data                = random_string.sandbox_access_token_hash_seed.result
  force_delete_without_recovery = var.allow_force_destroy

  lifecycle {
    ignore_changes = [secret_data]
  }
}

data "alicloud_kms_secret" "sandbox_access_token_hash_seed" {
  secret_name = alicloud_kms_secret.sandbox_access_token_hash_seed.secret_name
  depends_on  = [alicloud_kms_secret.sandbox_access_token_hash_seed]
}

output "sandbox_access_token_hash_seed" {
  value     = data.alicloud_kms_secret.sandbox_access_token_hash_seed.secret_data
  sensitive = true
}

# ---
# Redis cluster URL / TLS CA
# ---
resource "alicloud_kms_secret" "redis_cluster_url" {
  secret_name                = "${var.prefix}redis-cluster-url"
  secret_data_type           = "text"
  version_id                 = "v1"
  secret_data                = " "
  force_delete_without_recovery = var.allow_force_destroy

  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "alicloud_kms_secret" "redis_tls_ca_base64" {
  secret_name                = "${var.prefix}redis-tls-ca-base64"
  secret_data_type           = "text"
  version_id                 = "v1"
  secret_data                = " "
  force_delete_without_recovery = var.allow_force_destroy

  lifecycle {
    ignore_changes = [secret_data]
  }
}

output "redis_cluster_url_secret_name" {
  value = alicloud_kms_secret.redis_cluster_url.secret_name
}

output "redis_tls_ca_base64_secret_name" {
  value = alicloud_kms_secret.redis_tls_ca_base64.secret_name
}
