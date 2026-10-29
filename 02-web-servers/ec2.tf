####################################################################
# EC2 web servers + réseau associé
# EC2 web servers and their network resources
####################################################################

# --- Clé SSH / SSH key pair ----------------------------------------
resource "aws_key_pair" "web" {
  key_name   = "${var.tag}-${random_pet.test.id}"
  public_key = var.pub_ssh_key

  tags = local.tags
}

# --- Groupe de sécurité / Security group ---------------------------
resource "aws_security_group" "web" {
  vpc_id = data.terraform_remote_state.aws_infra.outputs.vpc_id

  tags = {
    Name = "${var.tag}-web-${random_pet.test.id}"
  }
}

# SSH (22)
resource "aws_security_group_rule" "allow_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "TCP"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

# HTTP du site / Website HTTP port (8080)
resource "aws_security_group_rule" "allow_http_8080" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "TCP"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

# Sortie / Egress (tout / all)
resource "aws_security_group_rule" "allow_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

# --- AMI RHEL officielle (Red Hat) / Official RHEL AMI (Red Hat) ---
data "aws_ami" "rhel" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat

  filter {
    name   = "name"
    values = ["RHEL-${var.rhel_major_version}.*_HVM-*-x86_64-*-Hourly2-GP3"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Instances EC2 (serveurs web) / EC2 web servers ----------------
resource "aws_instance" "web_server" {
  count         = var.num_web_servers
  ami           = data.aws_ami.rhel.id
  instance_type = "t3.micro"
  # element() reboucle sur la liste : 5 instances sur 3 subnets → 0,1,2,0,1
  # element() wraps around: 5 instances on 3 subnets → 0,1,2,0,1
  subnet_id                   = element(data.terraform_remote_state.aws_infra.outputs.subnet[*].id, count.index)
  key_name                    = aws_key_pair.web.key_name
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true

  tags = {
    Name = "${var.tag}-web_server-${random_pet.test.id}-${count.index}"
  }

  # most_recent change à chaque nouvelle AMI Red Hat : on évite de recréer
  # les instances existantes à chaque publication.
  # most_recent moves with every new Red Hat AMI: avoid replacing existing
  # instances on every release.
  lifecycle {
    ignore_changes = [ami]
  }
}
