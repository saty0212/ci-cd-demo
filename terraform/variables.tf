variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "EC2 key pair name (optional for SSH)"
  type        = string
  default     = null
}

variable "aws_access_key" {
  description = "AWS access key for authentication"
  type        = string
}

variable "aws_secret_key" {
  description = "AWS secret key for authentication"
  type        = string
}
