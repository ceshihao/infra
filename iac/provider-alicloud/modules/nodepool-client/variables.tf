variable "prefix" {
  type = string
}

variable "name" {
  type        = string
  description = "Nodepool short name suffix (e.g. orch-build / orch-client)"
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
  type        = string
  default     = "ecs.ebmg7.32xlarge"
  description = "ECS instance family. Nested virtualization (KVM) requires bare-metal families ebmg* / ebmgn*."
}

variable "node_pool_name" {
  type        = string
  description = "Nomad node pool name for client nodes"
}

variable "node_labels" {
  description = "Labels to assign to nodes for scheduling purposes"
  type        = list(string)
}

variable "base_hugepages_percentage" {
  description = "The percentage of memory to use for preallocated hugepages."
  type        = number
  default     = 60
}

variable "nested_virtualization" {
  type        = bool
  default     = true
  description = "Whether nested virtualization is enabled. On AlibabaCloud this is implicit on bare-metal (ebmg*/ebmgn*); reported here only as a downstream toggle for the start script."
}

variable "boot_disk_size_gb" {
  type        = number
  default     = 500
  description = "System disk size in GB"
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
  type = string
}

variable "alicloud_acr_instance_id" {
  type        = string
  description = "ACR EE instance id (cri-xxx). Written into /etc/aliyun-acr-helper.conf for the docker credential helper."
}

variable "fc_kernels_bucket_name" {
  type = string
}

variable "fc_versions_bucket_name" {
  type = string
}

variable "fc_env_pipeline_bucket_name" {
  type = string
}

variable "fc_busybox_bucket_name" {
  type = string
}

variable "scripts_path" {
  type        = string
  description = "Path to the directory containing startup scripts. Defaults to in-module scripts."
  default     = ""
}
