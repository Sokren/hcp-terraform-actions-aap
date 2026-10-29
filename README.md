# Terraform actions with Ansible Automation Platform

This repository contains a demo that uses Terraform actions to run Red Hat Ansible Automation Platform (AAP) jobs from HCP Terraform or Terraform Enterprise. Terraform provisions RHEL web servers on AWS and registers them in an AAP inventory. AAP configures each server when Terraform creates it, updates the website when its content changes, and decommissions each server before Terraform destroys it.

## How the demo works

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

## Repository structure

The repository contains two Terraform configurations. Deploy them in the following order:

- `01-aws-network/`: AWS network with a VPC, three public subnets, an internet gateway, and routes.
- `02-web-servers/`: EC2 instances, security group, AAP inventory, group, hosts, and actions.
  - `playbooks/`: Ansible playbooks that the AAP job templates run.
  - `website/`: Static website that AAP deploys to the web servers.

## Requirements

You need the following accounts and tools:

- An HCP Terraform organization or a Terraform Enterprise instance. The `02-web-servers` workspace requires Terraform v1.16 or later.
- A Red Hat Ansible Automation Platform instance that the HCP Terraform or Terraform Enterprise workers can reach over HTTPS.
- An AWS account with permissions to create VPC and EC2 resources.
- A GitHub account to fork this repository.
- An SSH key pair. Terraform installs the public key on the instances, and AAP uses the private key to connect to them.

## Configure Ansible Automation Platform

Create the following objects in the `Default` organization. To use a different organization, update the `organization_name` and `name` arguments in `02-web-servers/aap.tf` and `02-web-servers/actions.tf`.

1. Create a project that points to your fork of this repository. Enable **Update Revision on Launch** so that each job uses the latest commit.
1. Create a machine credential with the username `ec2-user` and the private key of your SSH key pair.
1. Create the following job templates. For each template, select the project and the machine credential, and enable **Prompt on launch** for the **Inventory** and **Limit** fields.

   | Job template name | Playbook |
   | --- | --- |
   | `tfc_httpd-config` | `02-web-servers/playbooks/httpd-config.yml` |
   | `tfc_update` | `02-web-servers/playbooks/update.yml` |
   | `tfc_destroy` | `02-web-servers/playbooks/destroy.yml` |

1. Create a user for Terraform. The user needs permission to create inventories in the organization and to execute the three job templates.

Terraform creates the `hcp-terraform-actions-aap` inventory and its `web_servers` group. You do not need to create them.

## Configure HCP Terraform or Terraform Enterprise

Create two variable sets and two workspaces in your organization.

### Create the variable sets

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

### Create the network workspace

1. Create a workspace named `hcp-terraform-actions-aap-network` with a version control workflow that uses your fork.
1. In **Advanced options**, set **Terraform Working Directory** to `01-aws-network`.
1. Apply the `aws-creds` variable set to the workspace.
1. Add the following Terraform variables:

   | Variable | Example value | Description |
   | --- | --- | --- |
   | `tag` | `demo-aap` | Prefix for the AWS resource names. |
   | `region` | `us-east-1` | AWS region for all resources. |

1. In **Settings** > **General**, under **Remote state sharing**, share the state with the `hcp-terraform-actions-aap-web-servers` workspace.

### Create the web servers workspace

1. Create a workspace named `hcp-terraform-actions-aap-web-servers` with a version control workflow that uses your fork.
1. In **Advanced options**, set **Terraform Working Directory** to `02-web-servers`.
1. In **Settings** > **General**, set the Terraform version to 1.16 or later.
1. Apply the `aws-creds` and `aap-creds` variable sets to the workspace.
1. Add the following Terraform variables:

   | Variable | Required | Example value | Description |
   | --- | --- | --- | --- |
   | `tag` | Yes | `demo-aap` | Prefix for the AWS resource names. |
   | `region` | Yes | `us-east-1` | AWS region. Use the same region as the network workspace. |
   | `pub_ssh_key` | Yes | `ssh-ed25519 AAAA...` | Public key of your SSH key pair. |
   | `tfc_org` | Yes | `my-org` | Organization that contains the network workspace. |
   | `tfe_hostname` | No | `app.terraform.io` | Hostname of HCP Terraform or of your Terraform Enterprise instance. |
   | `network_workspace` | No | `hcp-terraform-actions-aap-network` | Name of the network workspace. |
   | `num_web_servers` | No | `2` | Number of web servers. The minimum is `1`. |
   | `rhel_major_version` | No | `10` | RHEL major version of the Amazon Machine Image (AMI). |

1. Optional: In **Settings** > **Run Triggers**, add `hcp-terraform-actions-aap-network` as a source workspace. A successful apply in the network workspace then starts a plan in this workspace.

## Deploy the demo

1. Start a run in the `hcp-terraform-actions-aap-network` workspace and apply the plan.
1. Start a run in the `hcp-terraform-actions-aap-web-servers` workspace and apply the plan. Terraform creates the instances and the AAP hosts, then runs one `tfc_httpd-config` job for each host.
1. Open one of the URLs from the `ec2_all_addr_aap_http` output. The page shows the website and the operating system version of the server.

The first apply can report a `Warning: Error making request` from the `health_check_http_AAP_8080` check. Terraform can run the check before AAP finishes the configuration of port `8080`. After the configuration job completes, the next health assessment reports a healthy status.

## Run the day 2 scenarios

After the deployment, use the following scenarios to show each action.

### Update the website

1. Edit a file in `02-web-servers/website/`, such as `index.html`.
1. Commit and push the change. The workspace starts a run.
1. Apply the plan. The plan shows an in-place update of `terraform_data.trigger`, and Terraform runs the `tfc_update` job on all web servers.

### Add a web server

1. Increase the `num_web_servers` variable, for example from `2` to `3`.
1. Start a run and apply the plan. Terraform creates the instance and runs the `tfc_httpd-config` job on the new host only.

The host variables change when you add a server, so Terraform also runs the `tfc_update` job on all hosts.

### Remove a web server

1. Decrease the `num_web_servers` variable.
1. Start a run and apply the plan. Before Terraform removes the host, the `tfc_destroy` job stops `httpd`, removes the website, and reports the number of requests that the server handled.

## Demo simplifications

This demo uses the following simplifications. Do not use them in production.

- The AAP provider skips TLS certificate verification with `insecure_skip_verify = true`.
- The security group allows SSH and HTTP on port `8080` from any address.
- The AWS credentials are static access keys. In production, use [dynamic provider credentials](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials).

## Clean up

Destroy the workspaces in the following order:

1. `hcp-terraform-actions-aap-web-servers`. Terraform runs the `tfc_destroy` job on each host, then removes the hosts, the inventory, and the instances.
1. `hcp-terraform-actions-aap-network`.

You can then delete the workspaces, the variable sets, and the AAP project, credential, job templates, and user.

## Next steps

- Learn how to [invoke an action](https://developer.hashicorp.com/terraform/language/invoke-actions) from the Terraform CLI.
- Review the [`action_trigger` reference](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle) for the list of events and `on_failure` modes.
- Review the [`aap_job_launch` action reference](https://registry.terraform.io/providers/ansible/aap/latest/docs) for the other job options.
