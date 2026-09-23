variable "aws_region" {
  description = "AWS region in which to create the host."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used for AWS resource names."
  type        = string
  default     = "chat-app"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Root disk size in GiB."
  type        = number
  default     = 20
}

variable "key_name" {
  description = "Name of the EC2 key pair."
  type        = string
  default     = "chat-app-deploy"
}

variable "ssh_public_key" {
  description = "Public key used by Ansible to access the instance."
  type        = string
  sensitive   = true
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH to the instance. Use your public IP/32."
  type        = string
}
