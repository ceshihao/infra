variable "prefix" {
  type = string
}

variable "alicloud_account_id" {
  type = string
}

variable "alicloud_region" {
  type = string
}

variable "cluster_tag_name" {
  type = string
}

variable "cluster_tag_value" {
  type = string
}

variable "cluster_node_policy_name" {
  type        = string
  description = "Name of the base cluster node RAM policy"
}

variable "cluster_node_assume_role_doc" {
  type        = string
  description = "JSON of the ECS assume role policy document"
}

variable "setup_bucket_name" {
  type = string
}

variable "setup_files_hash" {
  type = map(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "vpc_private_subnets" {
  type = list(string)
}

variable "image_family_prefix" {
  type    = string
  default = "e2b-orch-"
}

variable "cluster_size" {
  type    = number
  default = 1
}

variable "machine_type" {
  type    = string
  default = "ecs.g7.xlarge"
}

variable "node_pool_name" {
  type        = string
  description = "Nomad node pool name for this pool"
}

variable "consul_acl_token" {
  type      = string
  sensitive = true
}

variable "consul_gossip_encryption_key" {
  type      = string
  sensitive = true
}

variable "consul_dns_request_token" {
  type      = string
  sensitive = true
}

variable "alicloud_acr_account_repository_domain" {
  type        = string
  description = "ACR EE VPC domain, e.g. ${prefix}core-registry-vpc.${region}.cr.aliyuncs.com"
}

variable "alicloud_acr_instance_id" {
  type        = string
  description = "ACR EE instance id (cri-xxx). Written into /etc/aliyun-acr-helper.conf so the docker credential helper can call cr:GetAuthorizationToken via the ECS RAM Role."
}

variable "loki_bucket_name" {
  type        = string
  description = "OSS bucket name for Loki (used to derive RAM policy resource ARNs)"
}

variable "scripts_path" {
  type        = string
  description = "Path to the directory containing startup scripts. Defaults to in-module scripts."
  default     = ""
}
