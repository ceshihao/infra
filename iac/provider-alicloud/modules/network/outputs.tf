output "vpc_id" {
  value = alicloud_vpc.main.id
}

output "vpc_cidr_block" {
  value = alicloud_vpc.main.cidr_block
}

output "vpc_public_subnet_ids" {
  value = [for v in alicloud_vswitch.public : v.id]
}

output "vpc_private_subnet_ids" {
  value = [for v in alicloud_vswitch.private : v.id]
}

output "nat_eip_address" {
  value = alicloud_eip_address.nat.ip_address
}
