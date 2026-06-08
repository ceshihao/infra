locals {
  scripts_path = var.scripts_path != "" ? var.scripts_path : "${path.module}/scripts"

  user_data = templatefile("${local.scripts_path}/start-server.sh", {
    NUM_SERVERS                  = var.cluster_size
    CLUSTER_TAG_NAME             = var.cluster_tag_name
    CLUSTER_TAG_VALUE            = var.cluster_tag_value
    SCRIPTS_BUCKET               = var.setup_bucket_name
    NOMAD_TOKEN                  = var.nomad_acl_token
    CONSUL_TOKEN                 = var.consul_acl_token
    CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key

    RUN_CONSUL_FILE_HASH = var.setup_files_hash["run-consul"]
    RUN_NOMAD_FILE_HASH  = var.setup_files_hash["run-nomad"]
  })
}

# RAM Role bound to ECS through ess_scaling_configuration.role_name
resource "alicloud_ram_role" "control_server" {
  name        = "${var.prefix}control-server-node"
  document    = var.cluster_node_assume_role_doc
  description = "Nomad control server RAM role"
  force       = true
}

# AWS aws_iam_role_policy_attachment for_each → alicloud_ram_role_policy_attachment
resource "alicloud_ram_role_policy_attachment" "cluster_node" {
  policy_name = var.cluster_node_policy_name
  policy_type = "Custom"
  role_name   = alicloud_ram_role.control_server.name
}

# Custom image lookup; mirrors AWS data.aws_ami filter pattern.
data "alicloud_images" "control_server" {
  owners      = "self"
  name_regex  = "^${var.image_family_prefix}.*"
  most_recent = true
}

# AWS launch_template + autoscaling_group → alicloud ESS scaling_group + scaling_configuration.
# alicloud_ess_scaling_configuration is the canonical replacement for the AWS launch_template payload
# (image, instance_type, security_groups, user_data, role_name, tags). active=true makes it the
# group's effective configuration.
resource "alicloud_ess_scaling_group" "control_server" {
  scaling_group_name = "${var.prefix}control-server"
  vswitch_ids        = var.vpc_private_subnets

  min_size           = var.cluster_size
  max_size           = var.cluster_size
  default_cooldown   = 60
  removal_policies   = ["OldestInstance", "NewestInstance"]
  multi_az_policy    = "BALANCE"
}

resource "alicloud_ess_scaling_configuration" "control_server" {
  scaling_group_id  = alicloud_ess_scaling_group.control_server.id
  image_id          = data.alicloud_images.control_server.images[0].id
  instance_types    = [var.machine_type]
  security_group_ids = var.security_group_ids
  role_name         = alicloud_ram_role.control_server.name
  user_data         = local.user_data

  system_disk_category = "cloud_essd"
  system_disk_size     = 20

  force_delete = true
  active       = true
  enable       = true

  instance_name = "${var.prefix}orch-server"

  tags = {
    Name                  = "${var.prefix}orch-server"
    (var.cluster_tag_name) = var.cluster_tag_value
    "cluster-size"        = tostring(var.cluster_size)
  }

  lifecycle {
    create_before_destroy = true
  }
}
