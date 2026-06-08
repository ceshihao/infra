variable "prefix" {
  type = string
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "vpc_public_subnets" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  description = "CIDRs for the public vswitches in the VPC, at least three are required"
}

variable "vpc_private_subnets" {
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24", "10.0.14.0/24", "10.0.15.0/24", "10.0.16.0/24"]
  description = "CIDRs for the private vswitches in the VPC, at least three are required"
}

variable "vpc_availability_zones" {
  type        = list(string)
  description = "List of availability zones (e.g. cn-hangzhou-a) to spread vswitches across"
}
