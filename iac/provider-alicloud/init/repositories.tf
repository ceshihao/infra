# ----------------------------------------------------------------------------
# AlibabaCloud Container Registry (ACR) — Enterprise Edition
# Mirrors the 7 ECR repos defined in provider-aws/init/repositories.tf.
#
# Key differences vs AWS ECR:
#   - Enterprise Edition requires creating an instance (alicloud_cr_ee_instance) first,
#     then a namespace under it, then repositories under the namespace.
#   - Personal Edition (alicloud_cr_namespace + alicloud_cr_repo) has no instance concept
#     but is not recommended for production (no VPC private access / no signing / limited capacity).
#   - GetAuthorizationToken credentials expire in 1h (vs ECR 12h) → orchestrator/template-manager
#     must refresh before each build (see packages/.../oci/auth/alibabacloud.go).
# ----------------------------------------------------------------------------

resource "alicloud_cr_ee_instance" "core" {
  payment_type   = "Subscription"
  period         = var.acr_ee_period
  renewal_status = "ManualRenewal"
  instance_type  = var.acr_ee_instance_type
  instance_name  = "${var.prefix}core"

  # ⚠️ Basic instances do NOT support VPC private domain *-registry-vpc.*.cr.aliyuncs.com,
  #   and nomad/main.tf defaults to the VPC domain → must use Standard or above.
  # ⚠️ Subscription is prepaid; destroy does not refund — cancel manually in the ACR console.
}

resource "alicloud_cr_ee_namespace" "core" {
  instance_id        = alicloud_cr_ee_instance.core.id
  name               = "${var.prefix}core"
  auto_create        = false
  default_visibility = "PRIVATE"
}

# ---- Repositories (mirrors the 7 AWS ECR repos) ----

resource "alicloud_cr_ee_repo" "client_proxy" {
  instance_id = alicloud_cr_ee_instance.core.id
  namespace   = alicloud_cr_ee_namespace.core.name
  name        = "client-proxy"
  summary     = "client-proxy core image"
  repo_type   = "PRIVATE"
}

resource "alicloud_cr_ee_repo" "clickhouse_migrator" {
  instance_id = alicloud_cr_ee_instance.core.id
  namespace   = alicloud_cr_ee_namespace.core.name
  name        = "clickhouse-migrator"
  summary     = "clickhouse-migrator core image"
  repo_type   = "PRIVATE"
}

resource "alicloud_cr_ee_repo" "db_migrator" {
  instance_id = alicloud_cr_ee_instance.core.id
  namespace   = alicloud_cr_ee_namespace.core.name
  name        = "db-migrator"
  summary     = "db-migrator core image"
  repo_type   = "PRIVATE"
}

resource "alicloud_cr_ee_repo" "api" {
  instance_id = alicloud_cr_ee_instance.core.id
  namespace   = alicloud_cr_ee_namespace.core.name
  name        = "api"
  summary     = "api core image"
  repo_type   = "PRIVATE"
}

resource "alicloud_cr_ee_repo" "custom_environments" {
  instance_id = alicloud_cr_ee_instance.core.id
  namespace   = alicloud_cr_ee_namespace.core.name
  name        = "custom-environments"
  summary     = "User custom template images"
  repo_type   = "PRIVATE"
}

resource "alicloud_cr_ee_repo" "dashboard_api" {
  instance_id = alicloud_cr_ee_instance.core.id
  namespace   = alicloud_cr_ee_namespace.core.name
  name        = "dashboard-api"
  summary     = "dashboard-api core image"
  repo_type   = "PRIVATE"
}

resource "alicloud_cr_ee_repo" "docker_reverse_proxy" {
  instance_id = alicloud_cr_ee_instance.core.id
  namespace   = alicloud_cr_ee_namespace.core.name
  name        = "docker-reverse-proxy"
  summary     = "docker-reverse-proxy core image"
  repo_type   = "PRIVATE"
}
