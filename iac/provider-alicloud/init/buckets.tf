# ----------------------------------------------------------------------------
# OSS Buckets — mirrors the 11 S3 buckets in provider-aws/init/buckets.tf
# Notes:
#   - Bucket names are globally unique; use ${bucket_prefix}<role> (bucket_prefix already contains ${PREFIX}${ALICLOUD_ACCOUNT_ID}-)
#   - Server-side encryption enabled by default (KMS / OSS managed key)
#   - storage_class defaults to Standard; Loki/LB logs can use IA
# ----------------------------------------------------------------------------

resource "alicloud_oss_bucket" "setup" {
  bucket        = "${var.bucket_prefix}instance-setup"
  storage_class = "Standard"
  force_destroy = var.allow_force_destroy
}

resource "alicloud_oss_bucket" "fc_kernels" {
  bucket        = "${var.bucket_prefix}fc-kernels"
  storage_class = "Standard"
  force_destroy = var.allow_force_destroy
}

resource "alicloud_oss_bucket" "fc_versions" {
  bucket        = "${var.bucket_prefix}fc-versions"
  storage_class = "Standard"
  force_destroy = var.allow_force_destroy
}

resource "alicloud_oss_bucket" "fc_env_pipeline" {
  bucket        = "${var.bucket_prefix}fc-env-pipeline"
  storage_class = "Standard"
  force_destroy = var.allow_force_destroy
}

resource "alicloud_oss_bucket" "fc_busybox" {
  bucket        = "${var.bucket_prefix}fc-busybox"
  storage_class = "Standard"
  force_destroy = var.allow_force_destroy
}

resource "alicloud_oss_bucket" "fc_templates" {
  bucket        = "${var.bucket_prefix}fc-templates"
  storage_class = "Standard"
  force_destroy = var.allow_force_destroy
}

resource "alicloud_oss_bucket" "fc_template_build_cache" {
  bucket        = "${var.bucket_prefix}fc-build-cache"
  storage_class = "Standard"
  force_destroy = var.allow_force_destroy
}

# ---
# Loki — 8-day expiry
# ---
resource "alicloud_oss_bucket" "loki_storage" {
  bucket        = "${var.bucket_prefix}loki-storage"
  storage_class = "IA"
  force_destroy = var.allow_force_destroy

  lifecycle_rule {
    id      = "expire-objects-older-than-8-days"
    enabled = true
    prefix  = ""

    expiration {
      days = 8
    }
  }

  server_side_encryption_rule {
    sse_algorithm = "AES256"
  }
}

# ---
# Load Balancer access logs — 90-day expiry
# ALB can deliver access logs directly to OSS via access_log_record config;
# bucket policy authorization is handled by alicloud_log_project_oss_shipper or RAM role.
# ---
resource "alicloud_oss_bucket" "load_balancer_logs" {
  bucket        = "${var.bucket_prefix}load-balancer-logs"
  storage_class = "Standard"
  force_destroy = var.allow_force_destroy

  lifecycle_rule {
    id      = "expire-logs-older-than-90-days"
    enabled = true
    prefix  = ""

    expiration {
      days = 90
    }
  }

  server_side_encryption_rule {
    sse_algorithm = "AES256"
  }
}

# ---
# Clickhouse Backups — 30-day expiry
# ---
resource "alicloud_oss_bucket" "clickhouse_backups" {
  bucket        = "${var.bucket_prefix}clickhouse-backups"
  storage_class = "Standard"
  force_destroy = var.allow_force_destroy

  lifecycle_rule {
    id      = "expire-objects-older-than-30-days"
    enabled = true
    prefix  = ""

    expiration {
      days = 30
    }
  }
}
