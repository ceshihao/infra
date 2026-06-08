variable "alicloud_region" {
  type = string
}

variable "alicloud_profile" {
  type    = string
  default = "default"
}

# Default Ubuntu 24.04 public image. Image owner = "system" means AlibabaCloud official public images.
variable "source_image_owners" {
  type    = string
  default = "system"
}

variable "source_image_name_regex" {
  type    = string
  default = "^ubuntu_24_04_x64_20G_alibase_.*"
}

variable "prefix" {
  type = string
}

variable "consul_version" {
  type    = string
  default = "1.17.3"
}

variable "nomad_version" {
  type    = string
  default = "1.8.4"
}

variable "clickhouse_client_version" {
  type    = string
  default = "25.4.5.24"
}

variable "cni_plugin_version" {
  type    = string
  default = "v1.6.2"
}

# Temporary ECS instance type for Packer build (no nested virt needed; standard g7 is fine)
variable "base_instance_type" {
  type    = string
  default = "ecs.g7.large"
}

variable "vswitch_id" {
  type    = string
  default = ""
}
