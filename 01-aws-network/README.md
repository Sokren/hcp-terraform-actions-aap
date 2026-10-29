# 01-aws-network

[Français](#français) | [English](#english)

## Français

> [!WARNING]
> **Démo uniquement. N'utilisez pas cette configuration en production.**
> Le réseau est volontairement simplifié : tous les subnets sont publics, sans subnet privé, sans NAT gateway et sans VPC Flow Logs. Les versions des providers ne sont pas épinglées. Pour la liste des simplifications de la démo, consultez le [README principal](../README.md#demo-simplifications).

Cette configuration Terraform crée le réseau AWS de la démo. Le workspace `02-web-servers` lit ses outputs avec la data source `terraform_remote_state`. Déployez cette configuration en premier.

### Ressources créées

| Ressource | Description |
| --- | --- |
| `aws_vpc.main` | VPC `10.0.0.0/16` avec le support et les noms d'hôte DNS activés. |
| `aws_internet_gateway.this` | Passerelle Internet attachée au VPC. |
| `aws_subnet.public` | Un subnet public `/28` par zone de disponibilité, découpé dans `10.0.0.0/24`. |
| `aws_route_table.public` | Une table de routage par subnet public. |
| `aws_route_table_association.public_subnets` | Association de chaque subnet à sa table de routage. |
| `aws_route.public_internet_gateway` | Route `0.0.0.0/0` vers la passerelle Internet dans chaque table. |
| `random_pet.test` | Suffixe aléatoire ajouté aux noms des ressources. |

Les ressources portent le tag `Name` au format `<tag>-<random_pet>`. Les subnets et les tables de routage ajoutent le suffixe `-public-<index>`.

### Variables

| Variable | Obligatoire | Défaut | Description |
| --- | --- | --- | --- |
| `tag` | Oui | | Préfixe des noms des ressources AWS, par exemple `demo-aap`. |
| `region` | Oui | | Région AWS, par exemple `us-east-1`. Utilisez la même région dans le workspace `02-web-servers`. |
| `num_subnets_public` | Non | `3` | Nombre de subnets publics. La configuration calcule quatre plages `/28`, donc la valeur maximale est `4`. La région doit aussi avoir au moins autant de zones de disponibilité. |

### Outputs

| Output | Description |
| --- | --- |
| `vpc_id` | ID du VPC. Le workspace `02-web-servers` y crée le groupe de sécurité. |
| `subnet` | Objets complets des subnets publics. Le workspace `02-web-servers` répartit les instances EC2 sur leurs IDs. |

### Déployer avec HCP Terraform ou Terraform Enterprise

1. Dans **Projects**, créez un projet nommé `HCP Terraform Actions AAP`, s'il n'existe pas encore.
1. Dans ce projet, créez un workspace nommé `01-aws-network` avec un workflow VCS qui utilise votre fork du dépôt.
1. Dans **Advanced options**, définissez **Terraform Working Directory** sur `01-aws-network`.
1. Sous **VCS Triggers**, sélectionnez **Only trigger runs when files in specified paths change**, puis **Pattern-based triggers**, et ajoutez le pattern `/01-aws-network/**/*`.
1. Appliquez le variable set qui contient les identifiants AWS, par exemple `aws-creds`.
1. Ajoutez les variables Terraform `tag` et `region`.
1. Dans **Settings** > **General**, sous **Remote state sharing**, partagez le state avec le workspace `02-web-servers`.
1. Lancez un run et appliquez le plan.

La variable `network_workspace` du workspace `02-web-servers` vaut `01-aws-network` par défaut, soit le nom de ce workspace. Si vous utilisez un autre nom, modifiez cette variable.

Pour plus de détails sur l'ensemble de la démo, consultez le [README principal](../README.md).

### Nettoyer

Détruisez d'abord le workspace `02-web-servers`, puis ce workspace. Le VPC ne peut pas être supprimé tant que les instances EC2 et le groupe de sécurité existent.

## English

> [!WARNING]
> **Demo only. Do not use this configuration in production.**
> The network is deliberately simple: all subnets are public, with no private subnet, no NAT gateway, and no VPC Flow Logs. The provider versions are not pinned. For the list of demo simplifications, refer to the [main README](../README.md#demo-simplifications).

This Terraform configuration creates the AWS network for the demo. The `02-web-servers` workspace reads its outputs with the `terraform_remote_state` data source. Deploy this configuration first.

### Resources

| Resource | Description |
| --- | --- |
| `aws_vpc.main` | `10.0.0.0/16` VPC with DNS support and DNS hostnames enabled. |
| `aws_internet_gateway.this` | Internet gateway attached to the VPC. |
| `aws_subnet.public` | One `/28` public subnet per availability zone, carved out of `10.0.0.0/24`. |
| `aws_route_table.public` | One route table per public subnet. |
| `aws_route_table_association.public_subnets` | Associates each subnet with its route table. |
| `aws_route.public_internet_gateway` | `0.0.0.0/0` route to the internet gateway in each route table. |
| `random_pet.test` | Random suffix added to the resource names. |

The resources have a `Name` tag in the `<tag>-<random_pet>` format. Subnets and route tables add a `-public-<index>` suffix.

### Variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `tag` | Yes | | Prefix for the AWS resource names, for example `demo-aap`. |
| `region` | Yes | | AWS region, for example `us-east-1`. Use the same region in the `02-web-servers` workspace. |
| `num_subnets_public` | No | `3` | Number of public subnets. The configuration computes four `/28` ranges, so the maximum value is `4`. The region must also have at least that many availability zones. |

### Outputs

| Output | Description |
| --- | --- |
| `vpc_id` | ID of the VPC. The `02-web-servers` workspace creates its security group in this VPC. |
| `subnet` | Full objects of the public subnets. The `02-web-servers` workspace spreads the EC2 instances across their IDs. |

### Deploy with HCP Terraform or Terraform Enterprise

1. In **Projects**, create a project named `HCP Terraform Actions AAP`, if it does not exist yet.
1. In this project, create a workspace named `01-aws-network` with a version control workflow that uses your fork of the repository.
1. In **Advanced options**, set **Terraform Working Directory** to `01-aws-network`.
1. Under **VCS Triggers**, select **Only trigger runs when files in specified paths change**, select **Pattern-based triggers**, and add the `/01-aws-network/**/*` pattern.
1. Apply the variable set that contains your AWS credentials, for example `aws-creds`.
1. Add the `tag` and `region` Terraform variables.
1. In **Settings** > **General**, under **Remote state sharing**, share the state with the `02-web-servers` workspace.
1. Start a run and apply the plan.

The `network_workspace` variable of the `02-web-servers` workspace defaults to `01-aws-network`, the name of this workspace. If you use another name, change this variable.

For details about the whole demo, refer to the [main README](../README.md).

### Clean up

Destroy the `02-web-servers` workspace first, then this workspace. AWS cannot delete the VPC while the EC2 instances and the security group still exist.
