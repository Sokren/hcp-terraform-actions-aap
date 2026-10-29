####################################################################
# Intégration AAP : inventaire, groupe, hosts et trigger de relance
# AAP integration: inventory, group, hosts and re-run trigger
####################################################################

provider "aap" {
  host                 = var.aap_host_url
  username             = var.aap_username
  password             = var.aap_password
  insecure_skip_verify = true
}

# Organisation AAP existante / Existing AAP organization
data "aap_organization" "default" {
  name = "Default" # Ajustez si nécessaire / Adjust if needed
}

# Inventaire dédié à la démo, créé par Terraform
# Demo-dedicated inventory, created by Terraform
resource "aap_inventory" "web_servers" {
  name         = "hcp-terraform-actions-aap"
  description  = "Web servers managed by HCP Terraform actions"
  organization = data.aap_organization.default.id
}

# Groupe regroupant les serveurs web / Group holding the web servers
resource "aap_group" "web_servers" {
  inventory_id = aap_inventory.web_servers.id
  name         = "web_servers"
  description  = "RHEL web servers provisioned by Terraform"
}

# Ajoute chaque instance EC2 à l'inventaire / Add each EC2 instance to the inventory
resource "aap_host" "host" {
  for_each     = { for idx, instance in aws_instance.web_server : idx => instance }
  inventory_id = aap_inventory.web_servers.id
  groups       = toset([aap_group.web_servers.id])
  name         = each.value.public_ip
  description  = "Host provisioned by Terraform"
  variables = jsonencode({
    ansible_user = "ec2-user"
    public_ip    = each.value.public_ip
    target_hosts = each.value.public_ip
  })

  # Une fois l'hôte ajouté à l'inventaire, on lance le job de config httpd
  # ciblé sur CET hôte. Puis, avant de le retirer, le job de destruction
  # ciblé lui aussi sur CET hôte (via `caller.name` dans les actions).
  # After the host is added to the inventory, run the httpd config job scoped
  # to THIS host. Before it is removed, run the teardown job also scoped to it.
  lifecycle {
    # En cas d'échec du job de config, l'hôte est marqué tainted : il sera
    # recréé au prochain apply et httpd-config sera rejoué.
    # If the config job fails, the host is tainted: it is recreated on the
    # next apply and httpd-config runs again.
    action_trigger {
      events     = [after_create]
      actions    = [action.aap_job_launch.create]
      on_failure = taint
    }
    # Un échec du job de destruction (instance injoignable, etc.) ne doit pas
    # bloquer le destroy : l'erreur est journalisée et Terraform continue.
    # A failed teardown job (unreachable instance, etc.) must not block the
    # destroy: the error is logged and Terraform carries on.
    action_trigger {
      events     = [before_destroy]
      actions    = [action.aap_job_launch.destroy]
      on_failure = continue
    }
  }

  # Les règles firewall doivent exister AVANT le job de config (after_create) et
  # survivre JUSQU'À la fin du job de destruction (before_destroy). Comme
  # depends_on s'inverse à la destruction, l'hôte (et ses actions) est traité
  # avant que les règles ne soient supprimées → le SSH reste ouvert.
  # Firewall rules must exist BEFORE the config job (after_create) and survive
  # UNTIL the teardown job finishes (before_destroy). Since depends_on reverses
  # on destroy, the host (and its actions) is handled before the rules are
  # removed → SSH stays open.
  depends_on = [
    aws_security_group.web,
    aws_security_group_rule.allow_ssh,
    aws_security_group_rule.allow_http_8080,
    aws_security_group_rule.allow_egress,
  ]
}

# Hash agrégé de tous les fichiers du site.
# Aggregated hash of every website file.
# Même dossier que celui déployé par les playbooks (playbooks/../website).
# Same folder the playbooks deploy (playbooks/../website).
locals {
  website_dir = "${path.module}/website"
  website_hash = sha256(join("", [
    for f in sort(fileset(local.website_dir, "**")) :
    filesha256("${local.website_dir}/${f}")
  ]))
}

# Mise à jour en place (et relance de l'action AAP update) dès qu'un input change.
# In-place update (re-running the AAP update action) whenever an input changes.
resource "terraform_data" "trigger" {
  input = join("-", [
    aap_inventory.web_servers.id,                          # inventaire / inventory
    data.aap_job_template.update_template.id,              # job template id
    jsonencode([for k, h in aap_host.host : h.variables]), # variables des hosts / host vars
    filesha256("${path.module}/playbooks/update.yml"),     # playbook
    local.website_hash,                                    # contenu du site / site content
  ])

  lifecycle {
    action_trigger {
      events  = [before_update]
      actions = [action.aap_job_launch.update]
    }
  }

  # aap_host.host dépend déjà des règles firewall (transitif).
  # aap_host.host already depends on the firewall rules (transitive).
  depends_on = [
    aap_host.host,
  ]
}
