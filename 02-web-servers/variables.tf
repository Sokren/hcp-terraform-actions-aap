####################################################################
# Locals & variables d'entrée
# Locals and input variables
####################################################################

locals {
  # Tag commun appliqué aux ressources / Common tag applied to resources
  tags = {
    Name = "${var.tag}-${random_pet.test.id}"
  }
}

# --- Général / General ---------------------------------------------
variable "tag" {
  type = string
}

variable "pub_ssh_key" {
  type = string
}

# Nombre d'instances web à créer (réparties en boucle sur les subnets)
# Number of web instances to create (spread round-robin across subnets)
variable "num_web_servers" {
  type    = number
  default = 2

  validation {
    condition     = var.num_web_servers >= 1
    error_message = "num_web_servers must be at least 1 (the health check targets web_server[0])."
  }
}

# Version majeure de RHEL pour l'AMI / RHEL major version for the AMI
variable "rhel_major_version" {
  type    = string
  default = "10"
}

variable "tfc_org" {
  type = string
}

# HCP Terraform (app.terraform.io) ou nom d'hôte Terraform Enterprise
# HCP Terraform (app.terraform.io) or Terraform Enterprise hostname
variable "tfe_hostname" {
  type    = string
  default = "app.terraform.io"
}

# Workspace qui déploie 01-aws-network / Workspace that deploys 01-aws-network
variable "network_workspace" {
  type    = string
  default = "hcp-terraform-actions-aap-network"
}

variable "region" {
  type = string
}

# --- AAP (Ansible Automation Platform) -----------------------------
variable "aap_host_url" {
  type = string
}

variable "aap_username" {
  type = string
}

variable "aap_password" {
  type      = string
  sensitive = true
}
