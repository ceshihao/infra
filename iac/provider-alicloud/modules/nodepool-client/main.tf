locals {
  scripts_path = var.scripts_path != "" ? var.scripts_path : "${path.module}/scripts"

  user_data = templatefile("${local.scripts_path}/start-client.sh", {
    NODE_POOL                    = var.node_pool_name
    CLUSTER_TAG_NAME             = var.cluster_tag_name
    CLUSTER_TAG_VALUE            = var.cluster_tag_value
    SCRIPTS_BUCKET               = var.setup_bucket_name
    CONSUL_TOKEN                 = var.consul_acl_token
    CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key
    CONSUL_DNS_REQUEST_TOKEN     = var.consul_dns_request_token

    FC_KERNELS_BUCKET_NAME      = var.fc_kernels_bucket_name
    FC_VERSIONS_BUCKET_NAME     = var.fc_versions_bucket_name
    FC_ENV_PIPELINE_BUCKET_NAME = var.fc_env_pipeline_bucket_name
    FC_BUSYBOX_BUCKET_NAME      = var.fc_busybox_bucket_name
    NODE_LABELS                 = join(",", var.node_labels)
    BASE_HUGEPAGES_PERCENTAGE   = var.base_hugepages_percentage
    NESTED_VIRTUALIZATION       = var.nested_virtualization

    ALIBABA_CLOUD_ACR_ACCOUNT_REPOSITORY_DOMAIN = var.alicloud_acr_account_repository_domain
    ALIBABA_CLOUD_ACR_INSTANCE_ID               = var.alicloud_acr_instance_id

    # ossfs mounts OSS bucket using ECS RAM Role to auto-fetch STS.
    # OSSFS_RAM_ROLE is equivalent to alicloud_ram_role.client.name below, written as literal to avoid implicit dependency cycles from locals referencing resources.
    ALIBABA_CLOUD_REGION = var.alicloud_region
    OSSFS_RAM_ROLE  = "${var.prefix}${var.name}-node"

    RUN_CONSUL_FILE_HASH = var.setup_files_hash["run-consul"]
    RUN_NOMAD_FILE_HASH  = var.setup_files_hash["run-nomad"]
  })
}

# Client/build node OSS / ACR permissions are already included in cluster_node_policy (see nomad-cluster/main.tf).
# Therefore only cluster_node_policy is attached here; no additional client_node_policy needed.
resource "alicloud_ram_role" "client" {
  name        = "${var.prefix}${var.name}-node"
  document    = var.cluster_node_assume_role_doc
  description = "Nomad ${var.name} client node RAM role"
  force       = true
}

resource "alicloud_ram_role_policy_attachment" "cluster_node" {
  policy_name = var.cluster_node_policy_name
  policy_type = "Custom"
  role_name   = alicloud_ram_role.client.name
}

data "alicloud_images" "client" {
  owners      = "self"
  name_regex  = "^${var.image_family_prefix}.*"
  most_recent = true
}

# Note: Nested virtualization (KVM nested) on AlibabaCloud is NOT a launch_template field,
# but determined by instance family:
#   - ebmg7 / ebmgn7 / ebmhfg7 etc. ("Shenlong" bare-metal instance families): native KVM, nested virt supported
#   - Standard g7/g8 shared-host instances: nested NOT supported
# Therefore var.nested_virtualization is only a flag in user_data for start-client.sh
# to fail-fast on instances that do not support nested virtualization.
resource "alicloud_ess_scaling_group" "client" {
  scaling_group_name = "${var.prefix}${var.name}"
  vswitch_ids        = var.vpc_private_subnets

  min_size           = var.cluster_size
  max_size           = var.cluster_size
  default_cooldown   = 60
  removal_policies   = ["OldestInstance", "NewestInstance"]
  multi_az_policy    = "BALANCE"
}

resource "alicloud_ess_scaling_configuration" "client" {
  scaling_group_id   = alicloud_ess_scaling_group.client.id
  image_id           = data.alicloud_images.client.images[0].id
  instance_types     = [var.machine_type]
  security_group_ids = var.security_group_ids
  role_name          = alicloud_ram_role.client.name
  user_data          = local.user_data

  system_disk_category = "cloud_essd"
  system_disk_size     = var.boot_disk_size_gb

  force_delete = true
  active       = true
  enable       = true

  instance_name = "${var.prefix}${var.name}"

  tags = {
    Name                  = "${var.prefix}${var.name}"
    (var.cluster_tag_name) = var.cluster_tag_value
  }

  lifecycle {
    create_before_destroy = true
  }
}
