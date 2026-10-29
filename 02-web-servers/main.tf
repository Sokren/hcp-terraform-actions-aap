####################################################################
# Terraform & providers
# Configuration Terraform et déclaration des providers
####################################################################

terraform {
  required_version = "~> v1.16.0"

  required_providers {
    aap = {
      source  = "ansible/aap"
      version = "1.5.0"
    }
  }
}

# Remote state of the network workspace (VPC, subnets, ...)
# State distant du workspace réseau (VPC, subnets, ...)
data "terraform_remote_state" "aws_infra" {
  backend = "remote"
  config = {
    hostname     = var.tfe_hostname
    organization = var.tfc_org
    workspaces = {
      name = var.network_workspace
    }
  }
}

provider "aws" {
  region = var.region
}

# Random suffix to keep resource names unique across runs
# Suffixe aléatoire pour garder des noms de ressources uniques entre les runs
resource "random_pet" "test" {
  length = 1
}
