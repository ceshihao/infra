# Minimal skeleton equivalent to provider-aws/modules/network:
#   - 1 VPC
#   - len(public_subnets)  public vswitches (each placed in the corresponding vpc_availability_zones index)
#   - len(private_subnets) private vswitches (round-robin across AZs)
#   - 1 NAT Gateway + 1 EIP + SNAT, shared internet egress for all private vswitches (equivalent to AWS single_nat_gateway)
#
# Differences from AWS:
#   1. AlibabaCloud VPC has no elasticache_subnet_group; Redis (Tair) instances bind vswitch_id lists directly.
#   2. AlibabaCloud has no EC2 Instance Connect Endpoint; equivalent capability is provided by OOS Session Manager (not implemented in this skeleton).
resource "alicloud_vpc" "main" {
  vpc_name   = "${var.prefix}vpc"
  cidr_block = var.vpc_cidr
}

resource "alicloud_vswitch" "public" {
  count = length(var.vpc_public_subnets)

  vpc_id       = alicloud_vpc.main.id
  cidr_block   = var.vpc_public_subnets[count.index]
  zone_id      = var.vpc_availability_zones[count.index % length(var.vpc_availability_zones)]
  vswitch_name = "${var.prefix}public-${count.index}"
}

resource "alicloud_vswitch" "private" {
  count = length(var.vpc_private_subnets)

  vpc_id       = alicloud_vpc.main.id
  cidr_block   = var.vpc_private_subnets[count.index]
  zone_id      = var.vpc_availability_zones[count.index % length(var.vpc_availability_zones)]
  vswitch_name = "${var.prefix}private-${count.index}"
}

# NAT Gateway must be attached to a public vswitch; nat_type=Enhanced is the recommended version.
resource "alicloud_nat_gateway" "main" {
  vpc_id           = alicloud_vpc.main.id
  vswitch_id       = alicloud_vswitch.public[0].id
  nat_gateway_name = "${var.prefix}nat"
  nat_type         = "Enhanced"
  payment_type     = "PayAsYouGo"
}

resource "alicloud_eip_address" "nat" {
  address_name         = "${var.prefix}nat-eip"
  payment_type         = "PayAsYouGo"
  internet_charge_type = "PayByTraffic"
}

resource "alicloud_eip_association" "nat" {
  allocation_id = alicloud_eip_address.nat.id
  instance_id   = alicloud_nat_gateway.main.id
}

# Single SNAT rule covers all private vswitches; switch to for_each if per-AZ traffic isolation is needed.
resource "alicloud_snat_entry" "private" {
  count = length(alicloud_vswitch.private)

  snat_table_id     = alicloud_nat_gateway.main.snat_table_ids
  source_vswitch_id = alicloud_vswitch.private[count.index].id
  snat_ip           = alicloud_eip_address.nat.ip_address
  depends_on        = [alicloud_eip_association.nat]
}
