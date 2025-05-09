##############################
# terraform/phase1-eks/variables.tf
##############################

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "Name for the EKS control plane"
  type        = string
  default     = "otel-demo-cluster"
}

variable "vpc_cidr" {
  description = "CIDR block for the custom VPC (/23 = 512 IPs)"
  type        = string
  default     = "10.0.0.0/23"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets (/24 each = 256 IPs)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "availability_zones" {
  description = "AZs for each public subnet"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

variable "node_count" {
  description = "Desired number of EKS worker nodes at creation"
  type        = number
  default     = 2
}

variable "min_node_count" {
  description = "Minimum number of EKS worker nodes for auto-scaling"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of EKS worker nodes for auto-scaling"
  type        = number
  default     = 4
}

variable "instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.large"
}
