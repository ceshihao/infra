locals {
  setup_files = {
    "scripts/run-consul.sh" = "run-consul",
    "scripts/run-nomad.sh"  = "run-nomad"
  }

  setup_files_hash = {
    "run-consul" = substr(filesha256("${path.module}/scripts/run-consul.sh"), 0, 5)
    "run-nomad"  = substr(filesha256("${path.module}/scripts/run-nomad.sh"), 0, 5)
  }

  cluster_tag_name  = "cluster-discovery-name"
  cluster_tag_value = "${var.prefix}nomad-cluster"

  # Equivalent to AWS ${aws_account_id}.dkr.ecr.${region}.amazonaws.com:
  # ACR EE VPC internal: ${instance_name}-registry-vpc.${region}.cr.aliyuncs.com
  # Public: ${instance_name}-registry.${region}.cr.aliyuncs.com
  # Here we use ${prefix}core as the ACR EE instance_name (aligned with init/repositories.tf)
  alicloud_acr_account_repository_domain = "${var.prefix}core-registry-vpc.${var.alicloud_region}.cr.aliyuncs.com"
}

data "alicloud_account" "current" {}

data "alicloud_regions" "current" {
  current = true
}

data "alicloud_oss_bucket" "setup" {
  bucket = var.setup_bucket_name
}

# Upload run-consul.sh / run-nomad.sh to setup bucket; pulled by user_data on boot.
# Equivalent to AWS aws_s3_object; OSS objects lack native etag-triggered updates,
# so filename hash suffix is used to trigger instance recreation.
resource "alicloud_oss_bucket_object" "setup_config" {
  for_each = local.setup_files

  bucket = var.setup_bucket_name
  key    = "${each.value}-${local.setup_files_hash[each.value]}.sh"
  source = "${path.module}/${each.key}"
}

# ==== RAM Role + Policy (maps to AWS IAM) ====
#
# On AWS, a single IAM Role can attach multiple Policies; AlibabaCloud RAM works the same way.
# AlibabaCloud has no "instance_profile" concept; ECS instances bind RAM Roles directly via
# ess_scaling_configuration.role_name; assume_role trust is defined in alicloud_ram_role.document.
data "alicloud_ram_policy_document" "cluster_node_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principal {
      type        = "Service"
      identifiers = ["ecs.aliyuncs.com"]
    }
  }
}

resource "alicloud_ram_role" "cluster_node_assume_role_doc" {
  # Skeleton placeholder only – stores the assume policy doc for reuse by nodepools.
  # Actual nodepools use data.alicloud_ram_policy_document.cluster_node_assume.document directly.
  name        = "${var.prefix}cluster-node-base"
  document    = data.alicloud_ram_policy_document.cluster_node_assume.document
  description = "Base assume-role doc shared by nomad cluster nodepool RAM roles"
  force       = true
}

# Cluster-wide policy (attached to every node): OSS setup bucket / ACR / fc_* / templates / instance describe
data "alicloud_ram_policy_document" "cluster_node_policy" {
  statement {
    effect = "Allow"
    actions = [
      "oss:ListObjects",
      "oss:GetObject",
    ]
    resources = [
      "acs:oss:*:*:${var.setup_bucket_name}",
      "acs:oss:*:*:${var.setup_bucket_name}/*",
    ]
  }

  # ACR EE: push/pull custom images
  statement {
    effect = "Allow"
    actions = [
      "cr:GetAuthorizationToken",
      "cr:PullRepository",
      "cr:PushRepository",
      "cr:CreateRepository",
      "cr:GetRepository",
      "cr:ListRepository",
      "cr:DeleteImage",
    ]
    resources = ["*"]
  }

  # Binary bucket read access
  statement {
    effect = "Allow"
    actions = [
      "oss:ListObjects",
      "oss:GetObject",
      "oss:GetBucketLocation",
    ]
    resources = [
      "acs:oss:*:*:${var.fc_env_pipeline_bucket_name}",
      "acs:oss:*:*:${var.fc_env_pipeline_bucket_name}/*",
      "acs:oss:*:*:${var.fc_kernels_bucket_name}",
      "acs:oss:*:*:${var.fc_kernels_bucket_name}/*",
      "acs:oss:*:*:${var.fc_versions_bucket_name}",
      "acs:oss:*:*:${var.fc_versions_bucket_name}/*",
      "acs:oss:*:*:${var.fc_busybox_bucket_name}",
      "acs:oss:*:*:${var.fc_busybox_bucket_name}/*",
    ]
  }

  # Templates / build cache read-write
  statement {
    effect = "Allow"
    actions = [
      "oss:ListObjects",
      "oss:GetObject",
      "oss:PutObject",
      "oss:DeleteObject",
    ]
    resources = [
      "acs:oss:*:*:${var.templates_bucket_name}",
      "acs:oss:*:*:${var.templates_bucket_name}/*",
      "acs:oss:*:*:${var.templates_build_cache_bucket_name}",
      "acs:oss:*:*:${var.templates_build_cache_bucket_name}/*",
    ]
  }

  # Node self-discovery: DescribeInstances replaces AWS ec2:DescribeInstances/DescribeTags
  statement {
    effect = "Allow"
    actions = [
      "ecs:DescribeInstances",
      "ecs:DescribeInstanceAttribute",
      "ecs:DescribeTags",
    ]
    resources = ["*"]
  }
}

resource "alicloud_ram_policy" "cluster_node_policy" {
  policy_name     = "${var.prefix}cluster-node-policy"
  policy_document = data.alicloud_ram_policy_document.cluster_node_policy.document
  force           = true
}

# ==== Nodepool assembly (fully mirrors the 4 AWS modules) ====
module "control_server" {
  source = "../modules/nodepool-control-server"

  prefix              = var.prefix
  alicloud_account_id = var.alicloud_account_id
  alicloud_region     = var.alicloud_region

  cluster_tag_name  = local.cluster_tag_name
  cluster_tag_value = local.cluster_tag_value

  cluster_node_policy_name      = alicloud_ram_policy.cluster_node_policy.policy_name
  cluster_node_assume_role_doc  = data.alicloud_ram_policy_document.cluster_node_assume.document

  setup_bucket_name = var.setup_bucket_name
  setup_files_hash  = local.setup_files_hash

  security_group_ids  = var.control_server_security_group_ids
  vpc_private_subnets = var.vpc_private_subnets

  image_family_prefix = var.control_server_image_family_prefix
  cluster_size        = var.control_server_cluster_size
  machine_type        = var.control_server_machine_type

  nomad_acl_token              = var.nomad_acl_token_secret
  consul_acl_token             = var.consul_acl_token_secret
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
}

module "api" {
  source = "../modules/nodepool-api"

  prefix              = var.prefix
  alicloud_account_id = var.alicloud_account_id
  alicloud_region     = var.alicloud_region

  cluster_tag_name  = local.cluster_tag_name
  cluster_tag_value = local.cluster_tag_value

  cluster_node_policy_name     = alicloud_ram_policy.cluster_node_policy.policy_name
  cluster_node_assume_role_doc = data.alicloud_ram_policy_document.cluster_node_assume.document

  setup_bucket_name = var.setup_bucket_name
  setup_files_hash  = local.setup_files_hash

  security_group_ids  = var.api_security_group_ids
  vpc_private_subnets = var.vpc_private_subnets

  image_family_prefix = var.api_image_family_prefix
  cluster_size        = var.api_cluster_size
  machine_type        = var.api_machine_type

  node_pool_name               = var.api_node_pool_name
  consul_acl_token             = var.consul_acl_token_secret
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token_secret

  alicloud_acr_account_repository_domain = local.alicloud_acr_account_repository_domain
  alicloud_acr_instance_id               = var.alicloud_acr_instance_id
  loki_bucket_name                       = var.loki_bucket_name
}

module "clickhouse" {
  source = "../modules/nodepool-clickhouse"

  prefix              = var.prefix
  alicloud_account_id = var.alicloud_account_id
  alicloud_region     = var.alicloud_region

  cluster_tag_name  = local.cluster_tag_name
  cluster_tag_value = local.cluster_tag_value

  cluster_node_policy_name     = alicloud_ram_policy.cluster_node_policy.policy_name
  cluster_node_assume_role_doc = data.alicloud_ram_policy_document.cluster_node_assume.document

  setup_bucket_name = var.setup_bucket_name
  setup_files_hash  = local.setup_files_hash

  security_group_ids = var.clickhouse_security_group_ids

  image_family_prefix = var.clickhouse_image_family_prefix
  cluster_size        = var.clickhouse_cluster_size
  machine_type        = var.clickhouse_machine_type

  node_pool_name                         = var.clickhouse_node_pool_name
  clickhouse_az                          = var.clickhouse_az
  clickhouse_subnet_id                   = var.clickhouse_subnet_id
  clickhouse_backups_bucket_name         = var.clickhouse_backups_bucket_name
  job_constraint_prefix                  = var.clickhouse_job_constraint_prefix
  consul_acl_token                       = var.consul_acl_token_secret
  consul_gossip_encryption_key           = var.consul_gossip_encryption_key
  consul_dns_request_token               = var.consul_dns_request_token_secret
  alicloud_acr_account_repository_domain = local.alicloud_acr_account_repository_domain
  alicloud_acr_instance_id               = var.alicloud_acr_instance_id
}

module "build" {
  source = "../modules/nodepool-client"

  name                = "orch-build"
  prefix              = var.prefix
  alicloud_account_id = var.alicloud_account_id
  alicloud_region     = var.alicloud_region

  cluster_tag_name  = local.cluster_tag_name
  cluster_tag_value = local.cluster_tag_value

  cluster_node_policy_name     = alicloud_ram_policy.cluster_node_policy.policy_name
  cluster_node_assume_role_doc = data.alicloud_ram_policy_document.cluster_node_assume.document

  setup_bucket_name = var.setup_bucket_name
  setup_files_hash  = local.setup_files_hash

  security_group_ids  = var.build_security_group_ids
  vpc_private_subnets = var.vpc_private_subnets

  image_family_prefix = var.build_image_family_prefix
  cluster_size        = var.build_cluster_size
  machine_type        = var.build_machine_type

  node_pool_name                         = var.build_node_pool_name
  node_labels                            = var.build_node_labels
  nested_virtualization                  = var.build_server_nested_virtualization
  consul_acl_token                       = var.consul_acl_token_secret
  consul_gossip_encryption_key           = var.consul_gossip_encryption_key
  consul_dns_request_token               = var.consul_dns_request_token_secret
  alicloud_acr_account_repository_domain = local.alicloud_acr_account_repository_domain
  alicloud_acr_instance_id               = var.alicloud_acr_instance_id

  fc_kernels_bucket_name      = var.fc_kernels_bucket_name
  fc_versions_bucket_name     = var.fc_versions_bucket_name
  fc_env_pipeline_bucket_name = var.fc_env_pipeline_bucket_name
  fc_busybox_bucket_name      = var.fc_busybox_bucket_name
}

module "client" {
  source = "../modules/nodepool-client"

  name                = "orch-client"
  prefix              = var.prefix
  alicloud_account_id = var.alicloud_account_id
  alicloud_region     = var.alicloud_region

  cluster_tag_name  = local.cluster_tag_name
  cluster_tag_value = local.cluster_tag_value

  cluster_node_policy_name     = alicloud_ram_policy.cluster_node_policy.policy_name
  cluster_node_assume_role_doc = data.alicloud_ram_policy_document.cluster_node_assume.document

  setup_bucket_name = var.setup_bucket_name
  setup_files_hash  = local.setup_files_hash

  security_group_ids  = var.client_security_group_ids
  vpc_private_subnets = var.vpc_private_subnets

  image_family_prefix = var.client_image_family_prefix
  cluster_size        = var.client_cluster_size
  machine_type        = var.client_machine_type

  node_pool_name                         = var.client_node_pool_name
  node_labels                            = var.client_node_labels
  base_hugepages_percentage              = var.client_base_hugepages_percentage
  nested_virtualization                  = var.client_server_nested_virtualization
  consul_acl_token                       = var.consul_acl_token_secret
  consul_gossip_encryption_key           = var.consul_gossip_encryption_key
  consul_dns_request_token               = var.consul_dns_request_token_secret
  alicloud_acr_account_repository_domain = local.alicloud_acr_account_repository_domain
  alicloud_acr_instance_id               = var.alicloud_acr_instance_id

  fc_kernels_bucket_name      = var.fc_kernels_bucket_name
  fc_versions_bucket_name     = var.fc_versions_bucket_name
  fc_env_pipeline_bucket_name = var.fc_env_pipeline_bucket_name
  fc_busybox_bucket_name      = var.fc_busybox_bucket_name
}
