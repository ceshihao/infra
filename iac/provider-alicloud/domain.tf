# Skeleton equivalent to provider-aws/domain.tf.
#
# Key differences:
#   1. AWS ACM has built-in DNS-01 auto-validation + renewal; AlibabaCloud certificates must be
#      manually applied or via ACME and uploaded to CAS.
#      This skeleton requires var.alicloud_acm_certificate_id to be generated externally (run acme-dns flow in CI/CD).
#   2. cloudflare_record value points to alicloud_alb_load_balancer.ingress.dns_name;
#      the ALB dns_name is a public L4 access point, same behavior as AWS ALB DNS.
locals {
  domain_parts        = split(".", var.domain_name)
  domain_is_subdomain = length(local.domain_parts) > 2
  domain_root         = local.domain_is_subdomain ? join(".", slice(local.domain_parts, length(local.domain_parts) - 2, length(local.domain_parts))) : var.domain_name
}

data "cloudflare_zone" "domain" {
  name = local.domain_root
}

resource "cloudflare_record" "routing" {
  zone_id = data.cloudflare_zone.domain.zone_id
  name    = "*.${var.domain_name}"
  type    = "CNAME"
  value   = alicloud_alb_load_balancer.ingress.dns_name
  ttl     = 3600
  proxied = false
}
