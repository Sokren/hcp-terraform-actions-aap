provider "aws" {
  region  = var.region
}

resource "random_pet" "test" {
  length = 1
}
