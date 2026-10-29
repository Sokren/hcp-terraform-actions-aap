# 02-web-servers

[Français](#français) | [English](#english)

## Français

> [!WARNING]
> **Démo uniquement. N'utilisez pas cette configuration en production.**
> La sécurité est volontairement simplifiée :
>
> - Le groupe de sécurité ouvre SSH (`22`) et HTTP (`8080`) à toutes les adresses (`0.0.0.0/0`).
> - Le provider AAP ne vérifie pas le certificat TLS (`insecure_skip_verify = true`).
> - Le site est servi en HTTP, sans TLS.
> - Les identifiants AWS sont des clés d'accès statiques. En production, utilisez les [dynamic provider credentials](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials).

Cette configuration Terraform crée des serveurs web RHEL sur AWS, les enregistre dans un inventaire Red Hat Ansible Automation Platform (AAP) et utilise des Terraform actions pour lancer des jobs AAP à chaque étape du cycle de vie des serveurs. Déployez d'abord la configuration [`01-aws-network`](../01-aws-network/).

### Fonctionnement

| Événement | Ressource déclencheuse | Action | Job template AAP | Portée |
| --- | --- | --- | --- | --- |
| Terraform ajoute un serveur | `aap_host.host`, `after_create` | `aap_job_launch.create` | `tfc_httpd-config` | Nouvel hôte uniquement |
| Le site ou `update.yml` change | `terraform_data.trigger`, `before_update` | `aap_job_launch.update` | `tfc_update` | Tous les hôtes de l'inventaire |
| Terraform retire un serveur | `aap_host.host`, `before_destroy` | `aap_job_launch.destroy` | `tfc_destroy` | Hôte retiré uniquement |

- Les actions `create` et `destroy` limitent le job à l'hôte déclencheur avec `limit = caller.name`.
- La ressource `terraform_data.trigger` combine l'ID de l'inventaire, l'ID du job template `tfc_update`, les variables des hôtes, le hash de `playbooks/update.yml` et le hash du dossier `website/`. Quand une de ces valeurs change, Terraform met à jour la ressource en place et lance le job de mise à jour.
- Si le job `tfc_httpd-config` échoue, Terraform marque l'hôte comme tainted (`on_failure = taint`). Le prochain apply recrée l'hôte et relance le job.
- Si le job `tfc_destroy` échoue, Terraform journalise l'erreur et continue la destruction (`on_failure = continue`).
- `aap_host.host` dépend des règles du groupe de sécurité. Le port SSH reste donc ouvert pendant le job de configuration et pendant le job de destruction.

### Fichiers

| Fichier | Contenu |
| --- | --- |
| `main.tf` | Version de Terraform, provider `ansible/aap`, provider AWS et lecture du state du workspace réseau. |
| `ec2.tf` | Paire de clés SSH, groupe de sécurité, AMI RHEL officielle et instances EC2. |
| `aap.tf` | Provider AAP, inventaire, groupe, hôtes et ressource `terraform_data.trigger`. |
| `actions.tf` | Data sources des job templates AAP et les trois actions `aap_job_launch`. |
| `checks.tf` | Check `health_check_http_AAP_8080` sur le premier serveur. |
| `variables.tf` | Variables d'entrée. |
| `outputs.tf` | Outputs. |
| `playbooks/` | Playbooks Ansible exécutés par les job templates AAP. |
| `website/` | Site statique déployé par AAP sur les serveurs. |

### Playbooks

| Playbook | Job template | Tâches |
| --- | --- | --- |
| `httpd-config.yml` | `tfc_httpd-config` | Installe `httpd`, passe le port d'écoute à `8080`, déploie `website/`, injecte la version de l'OS dans `index.html` et démarre `httpd`. |
| `update.yml` | `tfc_update` | Redéploie `website/` et injecte la version de l'OS dans `index.html`. |
| `destroy.yml` | `tfc_destroy` | Compte les requêtes servies, arrête `httpd` et supprime le site et le vhost. |

Les playbooks remplacent le texte `__OS_VERSION__` de `website/index.html` par la distribution et la version de l'OS du serveur.

### Prérequis

- Terraform v1.17.x. La contrainte `required_version = "~> v1.17.0"` refuse les versions 1.18 et ultérieures.
- Le workspace `01-aws-network` appliqué, avec son state partagé avec ce workspace.
- Une instance AAP joignable en HTTPS depuis les workers HCP Terraform ou Terraform Enterprise, configurée selon la section suivante.

### Configurer Ansible Automation Platform

Créez les objets suivants dans l'organisation `Default`. Pour utiliser une autre organisation, modifiez les arguments `name` et `organization_name` dans `aap.tf` et `actions.tf`.

1. Créez les credentials :

   | Nom suggéré | Type | Contenu | Usage |
   | --- | --- | --- | --- |
   | `tfc_demo_ssh` | Machine | Utilisateur `ec2-user` et clé privée de votre paire de clés SSH. | Connexion SSH d'AAP aux serveurs web. |
   | `tfc_demo_github` | Source Control | Utilisateur GitHub et personal access token, ou clé SSH. | Accès d'AAP à votre fork. Facultatif si le fork est public. |

1. Créez un projet qui pointe vers votre fork :
   - **Source control type** : `Git`.
   - **Source control URL** : URL de votre fork.
   - **Source control branch** : `main`.
   - **Source control credential** : `tfc_demo_github`, si vous l'avez créé.
   - Activez **Update Revision on Launch** pour que chaque job utilise le dernier commit, notamment le contenu à jour de `website/`.

1. Créez les trois job templates. Pour chacun, sélectionnez le projet et le credential `tfc_demo_ssh`, et activez **Prompt on launch** pour les champs **Inventory** et **Limit**. Terraform transmet l'inventaire et, pour la création et la destruction, l'hôte ciblé.

   | Nom du job template | Playbook | Lancé par |
   | --- | --- | --- |
   | `tfc_httpd-config` | `02-web-servers/playbooks/httpd-config.yml` | `aap_job_launch.create` |
   | `tfc_update` | `02-web-servers/playbooks/update.yml` | `aap_job_launch.update` |
   | `tfc_destroy` | `02-web-servers/playbooks/destroy.yml` | `aap_job_launch.destroy` |

   Les noms doivent correspondre exactement à ceux de `actions.tf`.

1. Créez un utilisateur pour Terraform. Il doit pouvoir créer des inventaires dans l'organisation et exécuter les trois job templates. Renseignez ses identifiants dans les variables `aap_username` et `aap_password`.

Terraform crée l'inventaire `hcp-terraform-actions-aap` et son groupe `web_servers`. Ne les créez pas.

### Variables

| Variable | Obligatoire | Défaut | Description |
| --- | --- | --- | --- |
| `tag` | Oui | | Préfixe des noms des ressources AWS. |
| `region` | Oui | | Région AWS. Utilisez la même région que le workspace réseau. |
| `pub_ssh_key` | Oui | | Clé publique installée sur les instances. AAP utilise la clé privée correspondante. |
| `tfc_org` | Oui | | Organisation qui contient le workspace réseau. |
| `aap_host_url` | Oui | | URL de l'instance AAP. |
| `aap_username` | Oui | | Utilisateur AAP de Terraform. |
| `aap_password` | Oui | | Mot de passe de l'utilisateur AAP. Variable sensible. |
| `tfe_hostname` | Non | `app.terraform.io` | Nom d'hôte de HCP Terraform ou de votre instance Terraform Enterprise. |
| `network_workspace` | Non | `01-aws-network` | Nom du workspace qui déploie `01-aws-network`. La valeur par défaut correspond au nom du workspace réseau. |
| `num_web_servers` | Non | `2` | Nombre de serveurs web. La valeur minimale est `1`, car le health check cible le premier serveur. |
| `rhel_major_version` | Non | `10` | Version majeure de RHEL de l'AMI. |

Les instances sont réparties en boucle sur les subnets du workspace réseau. Terraform ignore les changements d'AMI après la création, pour ne pas remplacer les instances à chaque nouvelle AMI Red Hat.

### Outputs

| Output | Description |
| --- | --- |
| `ec2_all_addr` | Adresses IP publiques des serveurs. |
| `ec2_all_addr_aap_http` | URLs du site sur le port `8080`. |
| `inventory_details_with_name_and_org_name` | ID, nom et organisation de l'inventaire AAP. |
| `trigger_input` | Valeur courante de `terraform_data.trigger`, utile pour le débogage. |

### Déployer

1. Dans le projet `HCP Terraform Actions AAP`, créez un workspace nommé `02-web-servers` avec un workflow VCS qui utilise votre fork.
1. Dans **Advanced options**, définissez **Terraform Working Directory** sur `02-web-servers`.
1. Sous **VCS Triggers**, sélectionnez **Only trigger runs when files in specified paths change**, puis **Pattern-based triggers**, et ajoutez le pattern `/02-web-servers/**/*`. Le pattern inclut les dossiers `website/` et `playbooks/` : une modification du site lance donc un run.
1. Dans **Settings** > **General**, définissez la version de Terraform sur 1.17.x.
1. Appliquez les variable sets des identifiants AWS et AAP, puis ajoutez les autres variables obligatoires.
1. Lancez un run et appliquez le plan. Terraform crée les instances et les hôtes AAP, puis lance un job `tfc_httpd-config` par hôte.
1. Ouvrez une des URLs de l'output `ec2_all_addr_aap_http`.

Le premier apply peut afficher `Warning: Error making request` pour le check `health_check_http_AAP_8080`. Terraform peut exécuter le check avant qu'AAP ait fini de configurer le port `8080`. Le prochain health assessment retourne un état sain.

Pour les scénarios day 2 et les limites de la démo, consultez le [README principal](../README.md#run-the-day-2-scenarios).

### Nettoyer

Détruisez ce workspace avant le workspace réseau. Terraform lance le job `tfc_destroy` sur chaque hôte, puis supprime les hôtes, l'inventaire et les instances.

## English

> [!WARNING]
> **Demo only. Do not use this configuration in production.**
> Security is deliberately simplified:
>
> - The security group opens SSH (`22`) and HTTP (`8080`) to any address (`0.0.0.0/0`).
> - The AAP provider skips TLS certificate verification (`insecure_skip_verify = true`).
> - The website is served over HTTP, without TLS.
> - The AWS credentials are static access keys. In production, use [dynamic provider credentials](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials).

This Terraform configuration creates RHEL web servers on AWS, registers them in a Red Hat Ansible Automation Platform (AAP) inventory, and uses Terraform actions to launch AAP jobs at each step of the server lifecycle. Deploy the [`01-aws-network`](../01-aws-network/) configuration first.

### How it works

| Event | Triggering resource | Action | AAP job template | Scope |
| --- | --- | --- | --- | --- |
| Terraform adds a server | `aap_host.host`, `after_create` | `aap_job_launch.create` | `tfc_httpd-config` | New host only |
| The website or `update.yml` changes | `terraform_data.trigger`, `before_update` | `aap_job_launch.update` | `tfc_update` | All hosts in the inventory |
| Terraform removes a server | `aap_host.host`, `before_destroy` | `aap_job_launch.destroy` | `tfc_destroy` | Removed host only |

- The `create` and `destroy` actions limit the job to the triggering host with `limit = caller.name`.
- The `terraform_data.trigger` resource combines the inventory ID, the ID of the `tfc_update` job template, the host variables, the hash of `playbooks/update.yml`, and the hash of the `website/` directory. When one of these values changes, Terraform updates the resource in place and launches the update job.
- If the `tfc_httpd-config` job fails, Terraform marks the host as tainted (`on_failure = taint`). The next apply recreates the host and runs the job again.
- If the `tfc_destroy` job fails, Terraform logs the error and continues the destroy operation (`on_failure = continue`).
- `aap_host.host` depends on the security group rules, so the SSH port stays open during the configuration job and during the decommission job.

### Files

| File | Contents |
| --- | --- |
| `main.tf` | Terraform version, `ansible/aap` provider, AWS provider, and remote state of the network workspace. |
| `ec2.tf` | SSH key pair, security group, official RHEL AMI, and EC2 instances. |
| `aap.tf` | AAP provider, inventory, group, hosts, and the `terraform_data.trigger` resource. |
| `actions.tf` | AAP job template data sources and the three `aap_job_launch` actions. |
| `checks.tf` | `health_check_http_AAP_8080` check on the first server. |
| `variables.tf` | Input variables. |
| `outputs.tf` | Outputs. |
| `playbooks/` | Ansible playbooks that the AAP job templates run. |
| `website/` | Static website that AAP deploys to the servers. |

### Playbooks

| Playbook | Job template | Tasks |
| --- | --- | --- |
| `httpd-config.yml` | `tfc_httpd-config` | Installs `httpd`, changes the listening port to `8080`, deploys `website/`, injects the OS version into `index.html`, and starts `httpd`. |
| `update.yml` | `tfc_update` | Redeploys `website/` and injects the OS version into `index.html`. |
| `destroy.yml` | `tfc_destroy` | Counts the served requests, stops `httpd`, and removes the website and the vhost. |

The playbooks replace the `__OS_VERSION__` text in `website/index.html` with the distribution and OS version of the server.

### Requirements

- Terraform v1.17.x. The `required_version = "~> v1.17.0"` constraint rejects version 1.18 and later.
- The `01-aws-network` workspace applied, with its state shared with this workspace.
- An AAP instance that the HCP Terraform or Terraform Enterprise workers can reach over HTTPS, configured as described in the next section.

### Configure Ansible Automation Platform

Create the following objects in the `Default` organization. To use a different organization, update the `name` and `organization_name` arguments in `aap.tf` and `actions.tf`.

1. Create the credentials:

   | Suggested name | Type | Contents | Purpose |
   | --- | --- | --- | --- |
   | `tfc_demo_ssh` | Machine | Username `ec2-user` and the private key of your SSH key pair. | SSH connection from AAP to the web servers. |
   | `tfc_demo_github` | Source Control | GitHub username and personal access token, or an SSH key. | AAP access to your fork. Optional if the fork is public. |

1. Create a project that points to your fork:
   - **Source control type**: `Git`.
   - **Source control URL**: the URL of your fork.
   - **Source control branch**: `main`.
   - **Source control credential**: `tfc_demo_github`, if you created it.
   - Enable **Update Revision on Launch** so that each job uses the latest commit, including the current content of `website/`.

1. Create the three job templates. For each template, select the project and the `tfc_demo_ssh` credential, and enable **Prompt on launch** for the **Inventory** and **Limit** fields. Terraform passes the inventory and, for creation and decommission, the target host.

   | Job template name | Playbook | Launched by |
   | --- | --- | --- |
   | `tfc_httpd-config` | `02-web-servers/playbooks/httpd-config.yml` | `aap_job_launch.create` |
   | `tfc_update` | `02-web-servers/playbooks/update.yml` | `aap_job_launch.update` |
   | `tfc_destroy` | `02-web-servers/playbooks/destroy.yml` | `aap_job_launch.destroy` |

   The names must match the names in `actions.tf` exactly.

1. Create a user for Terraform. The user needs permission to create inventories in the organization and to execute the three job templates. Set its credentials in the `aap_username` and `aap_password` variables.

Terraform creates the `hcp-terraform-actions-aap` inventory and its `web_servers` group. Do not create them.

### Variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `tag` | Yes | | Prefix for the AWS resource names. |
| `region` | Yes | | AWS region. Use the same region as the network workspace. |
| `pub_ssh_key` | Yes | | Public key that Terraform installs on the instances. AAP uses the matching private key. |
| `tfc_org` | Yes | | Organization that contains the network workspace. |
| `aap_host_url` | Yes | | URL of the AAP instance. |
| `aap_username` | Yes | | AAP user for Terraform. |
| `aap_password` | Yes | | Password of the AAP user. Sensitive variable. |
| `tfe_hostname` | No | `app.terraform.io` | Hostname of HCP Terraform or of your Terraform Enterprise instance. |
| `network_workspace` | No | `01-aws-network` | Name of the workspace that deploys `01-aws-network`. The default value matches the name of the network workspace. |
| `num_web_servers` | No | `2` | Number of web servers. The minimum is `1`, because the health check targets the first server. |
| `rhel_major_version` | No | `10` | RHEL major version of the AMI. |

Terraform spreads the instances round-robin across the subnets of the network workspace. Terraform ignores AMI changes after creation, so a new Red Hat AMI does not replace the existing instances.

### Outputs

| Output | Description |
| --- | --- |
| `ec2_all_addr` | Public IP addresses of the servers. |
| `ec2_all_addr_aap_http` | Website URLs on port `8080`. |
| `inventory_details_with_name_and_org_name` | ID, name, and organization of the AAP inventory. |
| `trigger_input` | Current value of `terraform_data.trigger`, useful for debugging. |

### Deploy

1. In the `HCP Terraform Actions AAP` project, create a workspace named `02-web-servers` with a version control workflow that uses your fork.
1. In **Advanced options**, set **Terraform Working Directory** to `02-web-servers`.
1. Under **VCS Triggers**, select **Only trigger runs when files in specified paths change**, select **Pattern-based triggers**, and add the `/02-web-servers/**/*` pattern. The pattern includes the `website/` and `playbooks/` directories, so a change to the website starts a run.
1. In **Settings** > **General**, set the Terraform version to 1.17.x.
1. Apply the variable sets with the AWS and AAP credentials, then add the other required variables.
1. Start a run and apply the plan. Terraform creates the instances and the AAP hosts, then runs one `tfc_httpd-config` job for each host.
1. Open one of the URLs from the `ec2_all_addr_aap_http` output.

The first apply can report a `Warning: Error making request` from the `health_check_http_AAP_8080` check. Terraform can run the check before AAP finishes the configuration of port `8080`. The next health assessment reports a healthy status.

For the day 2 scenarios and the demo simplifications, refer to the [main README](../README.md#run-the-day-2-scenarios).

### Clean up

Destroy this workspace before the network workspace. Terraform runs the `tfc_destroy` job on each host, then removes the hosts, the inventory, and the instances.
