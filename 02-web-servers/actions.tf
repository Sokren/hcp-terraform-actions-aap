####################################################################
# Job templates AAP + actions de lancement
# AAP job templates and their launch actions
####################################################################

# --- Provisioning httpd par hôte / Per-host httpd provisioning -----
data "aap_job_template" "create_template" {
  name              = "tfc_httpd-config"
  organization_name = "Default" # Ajustez si nécessaire / Adjust if needed
}

# `caller` = l'instance aap_host qui déclenche l'action (after_create),
# on limite donc le job de config au seul hôte nouvellement ajouté.
# `caller` = the aap_host instance triggering the action (after_create),
# so we scope the config job to the newly added host only.
action "aap_job_launch" "create" {
  config {
    job_template_id                     = data.aap_job_template.create_template.id
    inventory_id                        = aap_inventory.web_servers.id
    limit                               = caller.name
    wait_for_completion                 = true
    wait_for_completion_timeout_seconds = 600
  }
}

# --- Destruction par hôte / Per-host teardown ----------------------
data "aap_job_template" "destroy_template" {
  name              = "tfc_destroy"
  organization_name = "Default" # Ajustez si nécessaire / Adjust if needed
}

# `caller` = l'instance aap_host qui déclenche l'action (before_destroy),
# on limite donc le job à ce seul hôte via `limit`.
# `caller` = the aap_host instance triggering the action (before_destroy),
# so we scope the job to that single host with `limit`.
action "aap_job_launch" "destroy" {
  config {
    job_template_id                     = data.aap_job_template.destroy_template.id
    inventory_id                        = aap_inventory.web_servers.id
    limit                               = caller.name
    wait_for_completion                 = true
    wait_for_completion_timeout_seconds = 600
  }
}

# --- Mise à jour du site / Website update --------------------------
data "aap_job_template" "update_template" {
  name              = "tfc_update"
  organization_name = "Default" # Ajustez si nécessaire / Adjust if needed
}

action "aap_job_launch" "update" {
  config {
    job_template_id                     = data.aap_job_template.update_template.id
    inventory_id                        = aap_inventory.web_servers.id
    wait_for_completion                 = true
    wait_for_completion_timeout_seconds = 600
  }
}
