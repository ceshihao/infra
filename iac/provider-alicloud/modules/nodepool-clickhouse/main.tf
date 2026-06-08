locals {
  scripts_path = var.scripts_path != "" ? var.scripts_path : "${path.module}/scripts"
}

# AWS aws_iam_policy_document -> alicloud_ram_policy_document
# ClickHouse backup bucket read-write permissions, mirrors AWS structure
data "alicloud_ram_policy_document" "clickhouse_node_policy" {
  statement {
    effect = "Allow"
    actions = [
      "oss:GetBucketInfo",
      "oss:ListObjects",
      "oss:DeleteObject",
      "oss:GetObject",
      "oss:PutObject",
      "oss:GetBucketLocation",
    ]
    resources = [
      "acs:oss:*:*:${var.clickhouse_backups_bucket_name}",
      "acs:oss:*:*:${var.clickhouse_backups_bucket_name}/*",
    ]
  }
}

resource "alicloud_ram_policy" "clickhouse_node_policy" {
  policy_name     = "${var.prefix}clickhouse-node-policy"
  policy_document = data.alicloud_ram_policy_document.clickhouse_node_policy.document
  force           = true
}

resource "alicloud_ram_role" "clickhouse" {
  name        = "${var.prefix}clickhouse-node"
  document    = var.cluster_node_assume_role_doc
  description = "Nomad ClickHouse node RAM role"
  force       = true
}

resource "alicloud_ram_role_policy_attachment" "cluster_node" {
  policy_name = var.cluster_node_policy_name
  policy_type = "Custom"
  role_name   = alicloud_ram_role.clickhouse.name
}

resource "alicloud_ram_role_policy_attachment" "clickhouse_node" {
  policy_name = alicloud_ram_policy.clickhouse_node_policy.policy_name
  policy_type = "Custom"
  role_name   = alicloud_ram_role.clickhouse.name
}

data "alicloud_images" "clickhouse" {
  owners      = "self"
  name_regex  = "^${var.image_family_prefix}.*"
  most_recent = true
}

# Persistent ESSD data disks – one per ClickHouse instance.
# AWS aws_ebs_volume → alicloud_ecs_disk; mount via alicloud_ecs_disk_attachment.
resource "alicloud_ecs_disk" "clickhouse" {
  for_each = toset([for i in range(1, var.cluster_size + 1) : tostring(i)])

  zone_id  = var.clickhouse_az
  size     = var.data_volume_size_gb
  category = "cloud_essd"

  disk_name = "${var.prefix}clickhouse-data-${each.key}"

  tags = {
    Name = "${var.prefix}clickhouse-data-${each.key}"
  }
}

# AWS aws_instance(for_each) + aws_volume_attachment equivalent.
# Does not use ESS scaling group: needs to stably attach the same ECS data disk to a fixed ClickHouse node.
resource "alicloud_instance" "clickhouse" {
  for_each = toset([for i in range(1, var.cluster_size + 1) : tostring(i)])

  image_id              = data.alicloud_images.clickhouse.images[0].id
  instance_type         = var.machine_type
  instance_name         = "${var.prefix}orch-clickhouse-${each.key}"
  host_name             = "${var.prefix}orch-clickhouse-${each.key}"
  availability_zone     = var.clickhouse_az
  vswitch_id            = var.clickhouse_subnet_id
  security_groups       = var.security_group_ids
  role_name             = alicloud_ram_role.clickhouse.name
  system_disk_category  = "cloud_essd"
  system_disk_size      = 20

  user_data = base64encode(templatefile("${local.scripts_path}/start-clickhouse.sh", {
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

    # AlibabaCloud data disk device path does not rely on AWS-style EBS volume id mapping;
    # the startup script can use lsblk to find unmounted cloud_essd devices, or read /dev/disk/by-id/.
    # DISK_ID placeholder kept so the startup script can look up by disk_name.
    DISK_ID = alicloud_ecs_disk.clickhouse[each.key].id
  }))

  tags = {
    Name                  = "${var.prefix}orch-clickhouse-${each.key}"
    (var.cluster_tag_name) = var.cluster_tag_value
    "job-constraint"      = "${var.job_constraint_prefix}-${each.key}"
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "alicloud_ecs_disk_attachment" "clickhouse" {
  for_each = toset([for i in range(1, var.cluster_size + 1) : tostring(i)])

  disk_id     = alicloud_ecs_disk.clickhouse[each.key].id
  instance_id = alicloud_instance.clickhouse[each.key].id
}
