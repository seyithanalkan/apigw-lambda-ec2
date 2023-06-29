variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "vpc_name" {
  type    = string
  default = "lambda-vpc"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "security_group_name" {
  type    = string
  default = "http-access"
}

variable "private_subnet" {
  default = 1
}

variable "public_subnet" {
  default = 1
}
