# Structurally equivalent to provider-aws/modules/cloudflare: only the secret backend is replaced with AlibabaCloud KMS Secret.
#
# Differences from AWS:
#   1. KMS Secret secret_data must use jsonencode; data source references by secret_name
#   2. Only the Cloudflare API token is stored here; DNS and zone resolution still use the cloudflare provider
resource "alicloud_kms_secret" "cloudflare" {
  secret_name      = "${var.prefix}cloudflare"
  secret_data_type = "text"
  version_id       = "v1"

  secret_data = jsonencode({
    TOKEN = ""
  })

  lifecycle {
    ignore_changes = [secret_data]
  }
}

data "alicloud_kms_secret" "cloudflare" {
  secret_name = alicloud_kms_secret.cloudflare.secret_name
  depends_on  = [alicloud_kms_secret.cloudflare]
}
