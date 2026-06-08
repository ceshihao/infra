variable "prefix" {
  type = string
}

variable "name" {
  type    = string
  default = "valkey"
}

variable "vpc_id" {
  type = string
}

variable "vswitch_ids" {
  type        = list(string)
  description = "Private vswitch ids that the Tair (Redis) instance is allowed to live in"
}

variable "port" {
  type    = number
  default = 6379
}

variable "instance_class" {
  type        = string
  description = "Tair / Redis instance class, e.g. redis.shard.small.ce or tair.rdb.with.proxy.large.ce"
}

variable "replica_size" {
  type        = number
  description = "Total nodes per shard including primary; aliyun calls this 'replica_count' (>=2 enables HA)"
}

variable "ingress_security_group_ids" {
  type = list(string)
}

variable "shard_count" {
  type        = number
  default     = 1
  description = "Number of shards; >1 enables cluster mode"
}

variable "engine_version" {
  type    = string
  default = "7.0"
}
