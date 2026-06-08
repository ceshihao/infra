locals {
  scripts_path = var.scripts_path != "" ? var.scripts_path : "${path.module}/scripts"

  user_data = templatefile("${local.scripts_path}/start-api.sh", {
    NODE_POOL                    = var.node_pool_name
    CLUSTER_TAG_NAME             = var.cluster_tag_name
    CLUSTER_TAG_VALUE            = var.cluster_tag_value
    SCRIPTS_BUCKET               = var.setup_bucket_name
    CONSUL_TOKEN                 = var.consul_acl_token
    CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key
    CONSUL_DNS_REQUEST_TOKEN     = var.consul_dns_request_token

    ALIBABA_CLOUD_ACR_ACCOUNT_REPOSITORY_DOMAIN = var.alicloud_acr_account_repository_domain
    ALIBABA_CLOUD_ACR_INSTANCE_ID               = var.alicloud_acr_instance_id
    ALIBABA_CLOUD_REGION                        = var.alicloud_region

    RUN_CONSUL_FILE_HASH = var.setup_files_hash["run-consul"]
    RUN_NOMAD_FILE_HASH  = var.setup_files_hash["run-nomad"]
  })
}

# AWS aws_iam_policy_document → alicloud_ram_policy_document
# Loki bucket write permission (API node specific, not attached to the cluster common policy)
data "alicloud_ram_policy_document" "api_node_policy" {
  statement {
    effect = "Allow"
    actions = [
      "oss:ListObjects",
      "oss:GetObject",
      "oss:PutObject",
      "oss:DeleteObject",
      "oss:GetBucketLocation",
    ]
    resources = [
      "acs:oss:*:*:${var.loki_bucket_name}",
      "acs:oss:*:*:${var.loki_bucket_name}/*",
    ]
  }
}

resource "alicloud_ram_policy" "api_node_policy" {
  policy_name     = "${var.prefix}api-node-policy"
  policy_document = data.alicloud_ram_policy_document.api_node_policy.document
  force           = true
}

resource "alicloud_ram_role" "api" {
  name        = "${var.prefix}api-node"
  document    = var.cluster_node_assume_role_doc
  description = "Nomad API node RAM role"
  force       = true
}

resource "alicloud_ram_role_policy_attachment" "cluster_node" {
  policy_name = var.cluster_node_policy_name
  policy_type = "Custom"
  role_name   = alicloud_ram_role.api.name
}

resource "alicloud_ram_role_policy_attachment" "api_node" {
  policy_name = alicloud_ram_policy.api_node_policy.policy_name
  policy_type = "Custom"
  role_name   = alicloud_ram_role.api.name
}

data "alicloud_images" "api" {
  owners      = "self"
  name_regex  = "^${var.image_family_prefix}.*"
  most_recent = true
}

resource "alicloud_ess_scaling_group" "api" {
  scaling_group_name = "${var.prefix}api"
  vswitch_ids        = var.vpc_private_subnets

  min_size           = var.cluster_size
  max_size           = var.cluster_size
  default_cooldown   = 60
  removal_policies   = ["OldestInstance", "NewestInstance"]
  multi_az_policy    = "BALANCE"
}

resource "alicloud_ess_scaling_configuration" "api" {
  scaling_group_id   = alicloud_ess_scaling_group.api.id
  image_id           = data.alicloud_images.api.images[0].id
  instance_types     = [var.machine_type]
  security_group_ids = var.security_group_ids
  role_name          = alicloud_ram_role.api.name
  user_data          = local.user_data

  system_disk_category = "cloud_essd"
  system_disk_size     = 20

  force_delete = true
  active       = true
  enable       = true

  instance_name = "${var.prefix}orch-api"

  tags = {
    Name                  = "${var.prefix}orch-api"
    (var.cluster_tag_name) = var.cluster_tag_value
  }

  lifecycle {
    create_before_destroy = true
  }
}
