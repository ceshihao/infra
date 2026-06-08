data "alicloud_account" "current" {}

# Network module (VPC + multiple vswitches). Implemented in ../modules/network:
#   - alicloud_vpc
#   - alicloud_vswitch × 3 zones
#   - alicloud_nat_gateway + alicloud_eip + alicloud_snat_entry (internet egress)
#   - alicloud_security_group ("instance_connect" equivalent to AWS EC2 Instance Connect inbound control;
#     on AlibabaCloud this is typically handled via OOS Session Manager / bastion; placeholder for now)
module "network" {
  source = "../modules/network"

  prefix                 = var.prefix
  vpc_availability_zones = ["${var.region}-a", "${var.region}-b", "${var.region}-c"]
}

# Cloudflare module reused directly (structurally equivalent to GCP/AWS provider).
# Note: For mainland China access, add alicloud_dcdn_domain / alicloud_alb acceleration layer outside the cloudflare module.
module "cloudflare" {
  source = "../modules/cloudflare"

  prefix = var.prefix
}
