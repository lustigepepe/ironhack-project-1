variable "azs" {
  description = "List of Availability Zones"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}
variable "project_name" {
  description = "Name of the project used for resource naming and tagging"
  type        = string
}

variable "instance_type" {
  description = "Type of the instance"
  type        = string
  default     = "t3.medium"
}
