####################################################################
# Outputs
####################################################################

# IPs publiques des serveurs / Public IPs of the servers
output "ec2_all_addr" {
  value = aws_instance.web_server[*].public_ip
}

# URLs du site servi par AAP (port 8080) / Site URLs served via AAP (port 8080)
output "ec2_all_addr_aap_http" {
  value = [for ip in aws_instance.web_server[*].public_ip : "http://${ip}:8080"]
}

# Détails de l'inventaire créé dans AAP / Details of the inventory created in AAP
output "inventory_details_with_name_and_org_name" {
  value = {
    id                = aap_inventory.web_servers.id
    name              = aap_inventory.web_servers.name
    organization_name = aap_inventory.web_servers.organization_name
  }
}

# Valeur courante du trigger (debug) / Current trigger value (debug)
output "trigger_input" {
  value = terraform_data.trigger.input
}
