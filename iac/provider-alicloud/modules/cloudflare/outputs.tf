locals {
  cloudflare_raw = jsondecode(data.alicloud_kms_secret.cloudflare.secret_data)
}

output "cloudflare" {
  value = {
    token = local.cloudflare_raw["TOKEN"]
  }
  sensitive = true
}
