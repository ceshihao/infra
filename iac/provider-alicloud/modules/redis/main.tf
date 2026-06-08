# Equivalent to provider-aws/modules/redis: managed Redis cluster (AlibabaCloud Tair / ApsaraDB for Redis Enterprise Edition)
#
# Key mapping:
#   AWS aws_elasticache_replication_group  ->  alicloud_kvstore_instance
#   transit_encryption_enabled = true      ->  ssl_enable = "Enable"
#   num_node_groups                        ->  shard_count (cluster_mode)
#   replicas_per_node_group + 1            ->  replica_count (total replicas per shard including the primary)
#
# CA certificate:
#   AlibabaCloud Tair TLS uses GlobalSign Root CA, equivalent to AWS using AmazonRootCA.
#   This skeleton uses GlobalSign Root R3 directly; for production consider using alicloud_kvstore_account with SSL CA download or ssl-ca data source.
resource "alicloud_kvstore_instance" "main" {
  db_instance_name = "${var.prefix}${var.name}"
  vswitch_id       = var.vswitch_ids[0]
  vpc_id           = var.vpc_id

  instance_class = var.instance_class
  instance_type  = "Redis"
  engine_version = var.engine_version

  # cluster mode supports shard_count > 1; use 1 for single-shard mode
  shard_count   = var.shard_count
  # replica_count includes primary; equivalent to AWS replicas_per_node_group + 1
  replica_count = var.replica_size

  port           = var.port
  ssl_enable     = "Enable"
  payment_type   = "PostPaid"
  security_ips   = ["0.0.0.0/0"] # Inbound traffic is already controlled by VPC security groups

  # Restrict access to specified security groups (equivalent to AWS aws_security_group ingress)
  security_group_id = join(",", var.ingress_security_group_ids)

  tags = {
    Name = "${var.prefix}${var.name}"
  }
}

# GlobalSign Root R3 — the root certificate used by AlibabaCloud Tair TLS.
# If the SDK trusts it by default, redis_tls_ca_base64 can be left empty,
# but keeping the explicit PEM maintains behavioral parity with the AWS module.
data "http" "globalsign_root_r3" {
  url = "https://secure.globalsign.com/cacert/root-r3.crt"
}

locals {
  redis_ca_pem_base64 = base64encode(data.http.globalsign_root_r3.response_body)
}
