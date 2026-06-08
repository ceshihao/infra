variable "prefix" {
  type = string
}

variable "bucket_prefix" {
  type = string
}

variable "allow_force_destroy" {
  default = false
}

variable "region" {
  type = string
}

variable "acr_ee_instance_type" {
  type    = string
  default = "Standard"
  description = <<-EOT
    ACR EE instance type. Basic does NOT support VPC private domain *-registry-vpc.*.cr.aliyuncs.com,
    and cluster nodes pull images via VPC, so Standard is the default. To save cost you can switch
    to Basic but must change acr_domain in main.tf / nomad/main.tf to the public domain *-registry.*.
  EOT
}

variable "acr_ee_period" {
  type    = number
  default = 1
  description = "ACR EE instance subscription period in months (>=1, prepaid monthly, destroy does not refund, cancel manually in the console)"
}
