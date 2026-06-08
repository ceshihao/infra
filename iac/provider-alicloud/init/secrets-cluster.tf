# ----------------------------------------------------------------------------
# Cluster bootstrap secret — Nomad ACL token / Consul ACL token /
# Consul DNS request token / Consul gossip encryption key
#
# Structurally equivalent to provider-aws/init/secrets-cluster.tf; only the
# secret backend is replaced with AlibabaCloud KMS.
#
# Notes:
#   - random_uuid / random_id are cloud-agnostic; reuse hashicorp/random provider directly.
#   - alicloud_kms_secret uses AlibabaCloud managed default key (alias/acs/kms); no standalone CMK needed.
#   - force_delete_without_recovery = true enables immediate deletion; otherwise 30-day recovery period applies.
# ----------------------------------------------------------------------------

resource "random_uuid" "nomad_acl_token" {}

resource "random_uuid" "consul_acl_token" {}

resource "random_uuid" "consul_dns_request_token" {}

resource "random_id" "consul_gossip_encryption_key" {
  byte_length = 32
}

resource "alicloud_kms_secret" "cluster" {
  secret_name                   = "${var.prefix}cluster"
  secret_data_type              = "text"
  version_id                    = "v1"
  force_delete_without_recovery = var.allow_force_destroy

  secret_data = jsonencode({
    NOMAD_ACL_TOKEN              = random_uuid.nomad_acl_token.result,
    CONSUL_ACL_TOKEN             = random_uuid.consul_acl_token.result,
    CONSUL_DNS_REQUEST_TOKEN     = random_uuid.consul_dns_request_token.result,
    CONSUL_GOSSIP_ENCRYPTION_KEY = random_id.consul_gossip_encryption_key.b64_std,
  })

  lifecycle {
    ignore_changes = [secret_data]
  }
}

data "alicloud_kms_secret" "cluster" {
  secret_name = alicloud_kms_secret.cluster.secret_name
  depends_on  = [alicloud_kms_secret.cluster]
}

locals {
  cluster_raw = jsondecode(data.alicloud_kms_secret.cluster.secret_data)
}

output "cluster" {
  sensitive = true
  value = {
    nomad_acl_token              = local.cluster_raw["NOMAD_ACL_TOKEN"]
    consul_acl_token             = local.cluster_raw["CONSUL_ACL_TOKEN"]
    consul_dns_request_token     = local.cluster_raw["CONSUL_DNS_REQUEST_TOKEN"]
    consul_gossip_encryption_key = local.cluster_raw["CONSUL_GOSSIP_ENCRYPTION_KEY"]
  }
}
