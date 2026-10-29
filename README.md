# Terraform actions with Ansible Automation Platform

[Français](#français) | [English](#english)

## Français

Ce dépôt contient une démo qui utilise les Terraform actions pour lancer des jobs Red Hat Ansible Automation Platform (AAP) depuis HCP Terraform ou Terraform Enterprise. Terraform crée des serveurs web RHEL sur AWS et les enregistre dans un inventaire AAP. AAP configure chaque serveur quand Terraform le crée, met à jour le site quand son contenu change, et décommissionne chaque serveur avant que Terraform ne le détruise.

> [!WARNING]
> **Démo uniquement. N'utilisez pas ce dépôt en production.**
> Les configurations simplifient la sécurité pour garder la démo courte : règles de groupe de sécurité ouvertes, pas de vérification TLS pour AAP et identifiants AWS statiques. Pour la liste complète, consultez [Simplifications de la démo](#simplifications-de-la-démo).

### Fonctionnement de la démo

Les Terraform actions exécutent une opération en dehors du cycle de vie normal des ressources. Un bloc `action_trigger`, dans le bloc `lifecycle` d'une ressource, invoque une action quand un événement du cycle de vie se produit. Cette démo utilise l'action `aap_job_launch` du [provider `ansible/aap`](https://registry.terraform.io/providers/ansible/aap/latest) pour lancer des job templates AAP.

| Événement | Ressource déclencheuse | Job template AAP | Portée |
| --- | --- | --- | --- |
| Terraform ajoute un serveur | `aap_host.host`, `after_create` | `tfc_httpd-config` | Nouvel hôte uniquement |
| Le site ou le playbook de mise à jour change | `terraform_data.trigger`, `before_update` | `tfc_update` | Tous les hôtes de l'inventaire |
| Terraform retire un serveur | `aap_host.host`, `before_destroy` | `tfc_destroy` | Hôte retiré uniquement |

Les actions de création et de destruction utilisent l'objet `caller` pour limiter le job AAP à l'hôte qui a déclenché l'action. La ressource `terraform_data.trigger` stocke un hash du dossier `website/` et de `update.yml`. Quand le hash change, Terraform met à jour la ressource en place et lance le job de mise à jour.

L'argument `on_failure` définit le comportement en cas d'échec d'un job AAP :

- Si le job de configuration échoue, Terraform marque l'hôte comme tainted. Le prochain apply recrée l'hôte et relance le job de configuration.
- Si le job de décommissionnement échoue, Terraform journalise l'erreur et continue la destruction.

### Structure du dépôt

Le dépôt contient deux configurations Terraform. Déployez-les dans l'ordre suivant :

- [`01-aws-network/`](01-aws-network/) : réseau AWS avec un VPC, trois subnets publics, une passerelle Internet et les routes.
- [`02-web-servers/`](02-web-servers/) : instances EC2, groupe de sécurité, inventaire, groupe et hôtes AAP, et actions.
  - `playbooks/` : playbooks Ansible exécutés par les job templates AAP.
  - `website/` : site statique déployé par AAP sur les serveurs web.

### Prérequis

Vous avez besoin des comptes et outils suivants :

- Une organisation HCP Terraform ou une instance Terraform Enterprise. Le workspace `02-web-servers` nécessite Terraform v1.17.x.
- Une instance Red Hat Ansible Automation Platform joignable en HTTPS depuis les workers HCP Terraform ou Terraform Enterprise.
- Un compte AWS avec les permissions de créer des ressources VPC et EC2.
- Un compte GitHub pour forker ce dépôt.
- Une paire de clés SSH. Terraform installe la clé publique sur les instances, et AAP utilise la clé privée pour s'y connecter.

### Configurer Ansible Automation Platform

Créez les objets suivants dans l'organisation `Default`. Pour utiliser une autre organisation, modifiez les arguments `organization_name` et `name` dans `02-web-servers/aap.tf` et `02-web-servers/actions.tf`.

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

1. Créez les trois job templates du tableau suivant. Appliquez les réglages suivants à chaque modèle :
   - **Project** : le projet de l'étape précédente.
   - **Credentials** : `tfc_demo_ssh`.
   - **Inventory** et **Limit** : activez **Prompt on launch**. Terraform transmet l'inventaire et, pour la création et la destruction, l'hôte ciblé.
   - **Options** > **Concurrent jobs** : activez cette option pour que les jobs s'exécutent en parallèle. Terraform lance en même temps un job `tfc_httpd-config` ou `tfc_destroy` par hôte. Sans cette option, AAP met les jobs en file d'attente et les exécute l'un après l'autre.

   | Nom du job template | Playbook | Lancé par |
   | --- | --- | --- |
   | `tfc_httpd-config` | `02-web-servers/playbooks/httpd-config.yml` | `aap_job_launch.create` |
   | `tfc_update` | `02-web-servers/playbooks/update.yml` | `aap_job_launch.update` |
   | `tfc_destroy` | `02-web-servers/playbooks/destroy.yml` | `aap_job_launch.destroy` |

   Les noms doivent correspondre exactement à ceux de `02-web-servers/actions.tf`.

1. Créez un utilisateur pour Terraform. Il doit pouvoir créer des inventaires dans l'organisation et exécuter les trois job templates. Renseignez ses identifiants dans les variables `aap_username` et `aap_password` du variable set `aap-creds`.

Terraform crée l'inventaire `hcp-terraform-actions-aap` et son groupe `web_servers`. Ne les créez pas.

### Configurer HCP Terraform ou Terraform Enterprise

Créez deux variable sets, un projet et deux workspaces dans votre organisation.

#### Créer les variable sets

Créez un variable set nommé `aws-creds` avec les variables d'environnement suivantes :

| Variable | Valeur | Catégorie | Sensible |
| --- | --- | --- | --- |
| `AWS_ACCESS_KEY_ID` | ID de votre clé d'accès AWS | Environment variable | Non |
| `AWS_SECRET_ACCESS_KEY` | Votre clé d'accès secrète AWS | Environment variable | Oui |

Créez un variable set nommé `aap-creds` avec les variables Terraform suivantes :

| Variable | Valeur | Catégorie | Sensible |
| --- | --- | --- | --- |
| `aap_host_url` | URL de votre instance AAP | Terraform variable | Non |
| `aap_username` | Nom de l'utilisateur AAP de Terraform | Terraform variable | Non |
| `aap_password` | Mot de passe de l'utilisateur AAP de Terraform | Terraform variable | Oui |

#### Créer le projet

Dans **Projects**, créez un projet nommé `HCP Terraform Actions AAP`. Créez les deux workspaces dans ce projet.

#### Créer le workspace réseau

1. Dans le projet `HCP Terraform Actions AAP`, créez un workspace nommé `01-aws-network` avec un workflow VCS qui utilise votre fork.
1. Dans **Advanced options**, définissez **Terraform Working Directory** sur `01-aws-network`.
1. Sous **VCS Triggers**, sélectionnez **Only trigger runs when files in specified paths change**, puis **Pattern-based triggers**, et ajoutez le pattern `/01-aws-network/*.tf`.
1. Appliquez le variable set `aws-creds` au workspace.
1. Ajoutez les variables Terraform suivantes :

   | Variable | Exemple de valeur | Description |
   | --- | --- | --- |
   | `tag` | `demo-aap` | Préfixe des noms des ressources AWS. |
   | `region` | `us-east-1` | Région AWS de toutes les ressources. |

1. Dans **Settings** > **General**, sous **Remote state sharing**, sélectionnez **Share with all workspaces in this project**. Le workspace `02-web-servers` n'existe pas encore : cette option lui donne accès au state dès sa création dans le projet `HCP Terraform Actions AAP`.

#### Créer le workspace des serveurs web

1. Dans le projet `HCP Terraform Actions AAP`, créez un workspace nommé `02-web-servers` avec un workflow VCS qui utilise votre fork.
1. Dans **Advanced options**, définissez **Terraform Working Directory** sur `02-web-servers`.
1. Sous **VCS Triggers**, sélectionnez **Only trigger runs when files in specified paths change**, puis **Pattern-based triggers**, et ajoutez le pattern `/02-web-servers/**/*`. Le pattern inclut les dossiers `website/` et `playbooks/` : une modification du site lance donc un run.
1. Dans **Settings** > **General**, définissez la version de Terraform sur 1.17.x.
1. Appliquez les variable sets `aws-creds` et `aap-creds` au workspace.
1. Ajoutez les variables Terraform suivantes :

   | Variable | Obligatoire | Exemple de valeur | Description |
   | --- | --- | --- | --- |
   | `tag` | Oui | `demo-aap` | Préfixe des noms des ressources AWS. |
   | `region` | Oui | `us-east-1` | Région AWS. Utilisez la même région que le workspace réseau. |
   | `pub_ssh_key` | Oui | `ssh-ed25519 AAAA...` | Clé publique de votre paire de clés SSH. |
   | `tfc_org` | Oui | `my-org` | Organisation qui contient le workspace réseau. |
   | `tfe_hostname` | Non | `app.terraform.io` | Nom d'hôte de HCP Terraform ou de votre instance Terraform Enterprise. |
   | `network_workspace` | Non | `01-aws-network` | Nom du workspace réseau. La valeur par défaut correspond au nom du workspace de la section précédente. |
   | `num_web_servers` | Non | `2` | Nombre de serveurs web. La valeur minimale est `1`. |
   | `rhel_major_version` | Non | `10` | Version majeure de RHEL de l'Amazon Machine Image (AMI). |

1. Facultatif : dans **Settings** > **Run Triggers**, ajoutez `01-aws-network` comme workspace source. Un apply réussi dans le workspace réseau lance alors un plan dans ce workspace.

### Déployer la démo

1. Lancez un run dans le workspace `01-aws-network` et appliquez le plan.
1. Lancez un run dans le workspace `02-web-servers` et appliquez le plan. Terraform crée les instances et les hôtes AAP, puis lance un job `tfc_httpd-config` par hôte.
1. Ouvrez une des URLs de l'output `ec2_all_addr_aap_http`. La page affiche le site et la version du système d'exploitation du serveur.

Le premier apply peut afficher `Warning: Error making request` pour le check `health_check_http_AAP_8080`. Terraform peut exécuter le check avant qu'AAP ait fini de configurer le port `8080`. Une fois le job de configuration terminé, le prochain health assessment retourne un état sain.

### Scénarios day 2

Après le déploiement, utilisez les scénarios suivants pour montrer chaque action.

#### Mettre à jour le site

1. Modifiez un fichier dans `02-web-servers/website/`, par exemple `index.html`.
1. Commitez et poussez la modification. Le workspace lance un run.
1. Appliquez le plan. Le plan affiche une mise à jour en place de `terraform_data.trigger`, et Terraform lance le job `tfc_update` sur tous les serveurs web.

#### Ajouter un serveur web

1. Augmentez la variable `num_web_servers`, par exemple de `2` à `3`.
1. Lancez un run et appliquez le plan. Terraform crée l'instance et lance le job `tfc_httpd-config` sur le nouvel hôte uniquement.

Les variables des hôtes changent quand vous ajoutez un serveur : Terraform lance donc aussi le job `tfc_update` sur tous les hôtes.

#### Retirer un serveur web

1. Diminuez la variable `num_web_servers`.
1. Lancez un run et appliquez le plan. Avant que Terraform ne retire l'hôte, le job `tfc_destroy` arrête `httpd`, supprime le site et indique le nombre de requêtes servies par le serveur.

### Simplifications de la démo

Cette démo utilise les simplifications suivantes. Ne les utilisez pas en production.

- Le provider AAP ne vérifie pas le certificat TLS (`insecure_skip_verify = true`).
- Le groupe de sécurité autorise SSH et HTTP sur le port `8080` depuis toutes les adresses.
- Les identifiants AWS sont des clés d'accès statiques. En production, utilisez les [dynamic provider credentials](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials).

### Nettoyer

Détruisez les workspaces dans l'ordre suivant :

1. `02-web-servers`. Terraform lance le job `tfc_destroy` sur chaque hôte, puis supprime les hôtes, l'inventaire et les instances.
1. `01-aws-network`.

Vous pouvez ensuite supprimer les workspaces, le projet `HCP Terraform Actions AAP`, les variable sets, ainsi que le projet, les credentials, les job templates et l'utilisateur AAP.

### Pour aller plus loin

- Découvrez comment [invoquer une action](https://developer.hashicorp.com/terraform/language/invoke-actions) depuis la CLI Terraform.
- Consultez la [référence `action_trigger`](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle) pour la liste des événements et des modes `on_failure`.
- Consultez la [référence de l'action `aap_job_launch`](https://registry.terraform.io/providers/ansible/aap/latest/docs) pour les autres options des jobs.

## English

This repository contains a demo that uses Terraform actions to run Red Hat Ansible Automation Platform (AAP) jobs from HCP Terraform or Terraform Enterprise. Terraform provisions RHEL web servers on AWS and registers them in an AAP inventory. AAP configures each server when Terraform creates it, updates the website when its content changes, and decommissions each server before Terraform destroys it.

> [!WARNING]
> **Demo only. Do not use this repository in production.**
> The configurations simplify security to keep the demo short: open security group rules, no TLS verification for AAP, and static AWS credentials. For the full list, refer to [Demo simplifications](#demo-simplifications).

### How the demo works

Terraform actions run an operation outside of the normal resource lifecycle. An `action_trigger` block in a resource's `lifecycle` block invokes an action when a lifecycle event occurs. This demo uses the `aap_job_launch` action from the [`ansible/aap` provider](https://registry.terraform.io/providers/ansible/aap/latest) to launch AAP job templates.

| Event | Triggering resource | AAP job template | Scope |
| --- | --- | --- | --- |
| Terraform adds a server | `aap_host.host`, `after_create` | `tfc_httpd-config` | New host only |
| The website or update playbook changes | `terraform_data.trigger`, `before_update` | `tfc_update` | All hosts in the inventory |
| Terraform removes a server | `aap_host.host`, `before_destroy` | `tfc_destroy` | Removed host only |

The create and destroy actions use the `caller` object to limit the AAP job to the host that triggered the action. The `terraform_data.trigger` resource stores a hash of the `website/` directory and of `update.yml`. When the hash changes, Terraform updates the resource in place and runs the update job.

The `on_failure` argument controls what happens when an AAP job fails:

- When the configuration job fails, Terraform marks the host as tainted. The next apply recreates the host and runs the configuration job again.
- When the decommission job fails, Terraform logs the error and continues the destroy operation.

### Repository structure

The repository contains two Terraform configurations. Deploy them in the following order:

- `01-aws-network/`: AWS network with a VPC, three public subnets, an internet gateway, and routes.
- `02-web-servers/`: EC2 instances, security group, AAP inventory, group, hosts, and actions.
  - `playbooks/`: Ansible playbooks that the AAP job templates run.
  - `website/`: Static website that AAP deploys to the web servers.

### Requirements

You need the following accounts and tools:

- An HCP Terraform organization or a Terraform Enterprise instance. The `02-web-servers` workspace requires Terraform v1.17.x.
- A Red Hat Ansible Automation Platform instance that the HCP Terraform or Terraform Enterprise workers can reach over HTTPS.
- An AWS account with permissions to create VPC and EC2 resources.
- A GitHub account to fork this repository.
- An SSH key pair. Terraform installs the public key on the instances, and AAP uses the private key to connect to them.

### Configure Ansible Automation Platform

Create the following objects in the `Default` organization. To use a different organization, update the `organization_name` and `name` arguments in `02-web-servers/aap.tf` and `02-web-servers/actions.tf`.

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

1. Create the three job templates in the following table. Apply the following settings to each template:
   - **Project**: the project from the previous step.
   - **Credentials**: `tfc_demo_ssh`.
   - **Inventory** and **Limit**: enable **Prompt on launch**. Terraform passes the inventory and, for creation and decommission, the target host.
   - **Options** > **Concurrent jobs**: enable it so that jobs run in parallel. Terraform launches one `tfc_httpd-config` or `tfc_destroy` job per host at the same time. Without this option, AAP queues the jobs and runs them one after the other.

   | Job template name | Playbook | Launched by |
   | --- | --- | --- |
   | `tfc_httpd-config` | `02-web-servers/playbooks/httpd-config.yml` | `aap_job_launch.create` |
   | `tfc_update` | `02-web-servers/playbooks/update.yml` | `aap_job_launch.update` |
   | `tfc_destroy` | `02-web-servers/playbooks/destroy.yml` | `aap_job_launch.destroy` |

   The names must match the names in `02-web-servers/actions.tf` exactly.

1. Create a user for Terraform. The user needs permission to create inventories in the organization and to execute the three job templates. Set its credentials in the `aap_username` and `aap_password` variables of the `aap-creds` variable set.

Terraform creates the `hcp-terraform-actions-aap` inventory and its `web_servers` group. Do not create them.

### Configure HCP Terraform or Terraform Enterprise

Create two variable sets, a project, and two workspaces in your organization.

#### Create the variable sets

Create a variable set named `aws-creds` with the following environment variables:

| Variable | Value | Category | Sensitive |
| --- | --- | --- | --- |
| `AWS_ACCESS_KEY_ID` | Your AWS access key ID | Environment variable | No |
| `AWS_SECRET_ACCESS_KEY` | Your AWS secret access key | Environment variable | Yes |

Create a variable set named `aap-creds` with the following Terraform variables:

| Variable | Value | Category | Sensitive |
| --- | --- | --- | --- |
| `aap_host_url` | The URL of your AAP instance | Terraform variable | No |
| `aap_username` | The username of the AAP user for Terraform | Terraform variable | No |
| `aap_password` | The password of the AAP user for Terraform | Terraform variable | Yes |

#### Create the project

In **Projects**, create a project named `HCP Terraform Actions AAP`. Create both workspaces in this project.

#### Create the network workspace

1. In the `HCP Terraform Actions AAP` project, create a workspace named `01-aws-network` with a version control workflow that uses your fork.
1. In **Advanced options**, set **Terraform Working Directory** to `01-aws-network`.
1. Under **VCS Triggers**, select **Only trigger runs when files in specified paths change**, select **Pattern-based triggers**, and add the `/01-aws-network/*.tf` pattern.
1. Apply the `aws-creds` variable set to the workspace.
1. Add the following Terraform variables:

   | Variable | Example value | Description |
   | --- | --- | --- |
   | `tag` | `demo-aap` | Prefix for the AWS resource names. |
   | `region` | `us-east-1` | AWS region for all resources. |

1. In **Settings** > **General**, under **Remote state sharing**, select **Share with all workspaces in this project**. The `02-web-servers` workspace does not exist yet, so this option lets it read the state as soon as you create it in the `HCP Terraform Actions AAP` project.

#### Create the web servers workspace

1. In the `HCP Terraform Actions AAP` project, create a workspace named `02-web-servers` with a version control workflow that uses your fork.
1. In **Advanced options**, set **Terraform Working Directory** to `02-web-servers`.
1. Under **VCS Triggers**, select **Only trigger runs when files in specified paths change**, select **Pattern-based triggers**, and add the `/02-web-servers/**/*` pattern. The pattern includes the `website/` and `playbooks/` directories, so a change to the website starts a run.
1. In **Settings** > **General**, set the Terraform version to 1.17.x.
1. Apply the `aws-creds` and `aap-creds` variable sets to the workspace.
1. Add the following Terraform variables:

   | Variable | Required | Example value | Description |
   | --- | --- | --- | --- |
   | `tag` | Yes | `demo-aap` | Prefix for the AWS resource names. |
   | `region` | Yes | `us-east-1` | AWS region. Use the same region as the network workspace. |
   | `pub_ssh_key` | Yes | `ssh-ed25519 AAAA...` | Public key of your SSH key pair. |
   | `tfc_org` | Yes | `my-org` | Organization that contains the network workspace. |
   | `tfe_hostname` | No | `app.terraform.io` | Hostname of HCP Terraform or of your Terraform Enterprise instance. |
   | `network_workspace` | No | `01-aws-network` | Name of the network workspace. The default value matches the workspace name from the previous section. |
   | `num_web_servers` | No | `2` | Number of web servers. The minimum is `1`. |
   | `rhel_major_version` | No | `10` | RHEL major version of the Amazon Machine Image (AMI). |

1. Optional: In **Settings** > **Run Triggers**, add `01-aws-network` as a source workspace. A successful apply in the network workspace then starts a plan in this workspace.

### Deploy the demo

1. Start a run in the `01-aws-network` workspace and apply the plan.
1. Start a run in the `02-web-servers` workspace and apply the plan. Terraform creates the instances and the AAP hosts, then runs one `tfc_httpd-config` job for each host.
1. Open one of the URLs from the `ec2_all_addr_aap_http` output. The page shows the website and the operating system version of the server.

The first apply can report a `Warning: Error making request` from the `health_check_http_AAP_8080` check. Terraform can run the check before AAP finishes the configuration of port `8080`. After the configuration job completes, the next health assessment reports a healthy status.

### Run the day 2 scenarios

After the deployment, use the following scenarios to show each action.

#### Update the website

1. Edit a file in `02-web-servers/website/`, such as `index.html`.
1. Commit and push the change. The workspace starts a run.
1. Apply the plan. The plan shows an in-place update of `terraform_data.trigger`, and Terraform runs the `tfc_update` job on all web servers.

#### Add a web server

1. Increase the `num_web_servers` variable, for example from `2` to `3`.
1. Start a run and apply the plan. Terraform creates the instance and runs the `tfc_httpd-config` job on the new host only.

The host variables change when you add a server, so Terraform also runs the `tfc_update` job on all hosts.

#### Remove a web server

1. Decrease the `num_web_servers` variable.
1. Start a run and apply the plan. Before Terraform removes the host, the `tfc_destroy` job stops `httpd`, removes the website, and reports the number of requests that the server handled.

### Demo simplifications

This demo uses the following simplifications. Do not use them in production.

- The AAP provider skips TLS certificate verification with `insecure_skip_verify = true`.
- The security group allows SSH and HTTP on port `8080` from any address.
- The AWS credentials are static access keys. In production, use [dynamic provider credentials](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials).

### Clean up

Destroy the workspaces in the following order:

1. `02-web-servers`. Terraform runs the `tfc_destroy` job on each host, then removes the hosts, the inventory, and the instances.
1. `01-aws-network`.

You can then delete the workspaces, the `HCP Terraform Actions AAP` project, the variable sets, and the AAP project, credentials, job templates, and user.

### Next steps

- Learn how to [invoke an action](https://developer.hashicorp.com/terraform/language/invoke-actions) from the Terraform CLI.
- Review the [`action_trigger` reference](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle) for the list of events and `on_failure` modes.
- Review the [`aap_job_launch` action reference](https://registry.terraform.io/providers/ansible/aap/latest/docs) for the other job options.
