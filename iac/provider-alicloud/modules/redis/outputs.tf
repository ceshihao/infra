output "endpoint_address" {
  value = alicloud_kvstore_instance.main.connection_domain
}

output "endpoint_ca_pem_base64" {
  value = local.redis_ca_pem_base64
}

output "instance_id" {
  value = alicloud_kvstore_instance.main.id
}
