locals {
  tags = {
    Name = "${var.tag}-${random_pet.test.id}"
  }

  pub_cidrs = cidrsubnets("10.0.0.0/24", 4, 4, 4, 4)
}

variable "tag" {
  type = string
}

variable "num_subnets_public" {
  default = 3
}

variable "region" {
  type = string
}
