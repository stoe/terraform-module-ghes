locals {
  root_volumn_size = var.ghes_root_volume_size < 200 ? 200 : var.ghes_root_volume_size

  data_volume_size = var.ghes_data_volume_size > 16000 ? 16000 : var.ghes_data_volume_size

  iops = var.ghes_data_volume_type == "io1" ? (
    var.ghes_data_volume_iops < (local.data_volume_size * 3) ? (
      (local.data_volume_size * 3) > 32000 ? 32000 : (local.data_volume_size * 3)
    ) : var.ghes_data_volume_iops
  ) : 0
}

resource "aws_security_group" "security_group" {
  # NOTE: https://docs.github.com/enterprise-server/admin/configuration/network-ports
  name        = format("%s-sg", var.name)
  description = "GitHub Enterprise Server Network Ports (https://help.github.com/enterprise/admin/installation/network-ports)"

  vpc_id = var.vpc_id

  tags = merge(
    map("Name", format("%s-sg", var.name)),
    var.tags
  )

  # outbound -----------------------------------------------------------------------------------------------------------
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "(internet) access: all"
  }

  # Monitoring
  egress {
    from_port   = var.ghes_logforwarding_port
    to_port     = var.ghes_logforwarding_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "log forwarding"
  }

  egress {
    from_port   = var.ghes_collectdforwarding_port
    to_port     = var.ghes_collectdforwarding_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "collectd"
  }

  # inbound ------------------------------------------------------------------------------------------------------------
  # Administrative ports
  ingress {
    from_port   = 8443
    to_port     = 8444
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS: Secure web-based Management Console. Required for basic installation and configuration."
  }

  ingress {
    from_port   = 8080
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP: Plain-text web-based Management Console. Not required unless SSL is disabled manually."
  }

  ingress {
    from_port   = 122
    to_port     = 122
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH: Shell access for your GitHub Enterprise Server instance. Required to be open to incoming connections from all other nodes in a High Availability configuration. The default SSH port (22) is dedicated to Git and SSH application network traffic."
  }

  ingress {
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "VPN: Secure replication network tunnel in High Availability configuration. Required to be open to all other nodes in the configuration."
  }

  ingress {
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "NTP: Required for time protocol operation."
  }

  ingress {
    from_port   = 161
    to_port     = 161
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SNMP: Required for network monitoring protocol operation."
  }

  # Application ports for end users
  ingress {
    from_port   = 443
    to_port     = 444
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS: Access to the web application and Git over HTTPS."
  }

  ingress {
    from_port   = 80
    to_port     = 81
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP: Access to the web application. All requests are redirected to the HTTPS port when SSL is enabled."
  }

  ingress {
    from_port   = 22
    to_port     = 23
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH: Access to Git over SSH. Supports clone, fetch, and push operations to public and public repositories."
  }

  ingress {
    from_port   = 9418
    to_port     = 9419
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Git: Git protocol port supports clone and fetch operations to public repositories with unencrypted network communication."
  }

  # Email ports
  ingress {
    from_port   = 25
    to_port     = 25
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SMTP: Support for SMTP with encryption (STARTTLS)."
  }
}

resource "aws_key_pair" "key_pair" {
  key_name   = "${var.name}-key"
  public_key = file(var.public_key_path)
}

data "aws_ami" "ami" {
  most_recent = true
  name_regex  = "^GitHub Enterprise (Server )?${var.ghes_version}"
  owners      = ["895557238572"] # GitHub

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# resource "aws_ami_copy" "ami_encrypted" {
#   # NOTE: GitHub AMI doesn't come with an encrypted root disk
#   #       Workaround by copying the AMI and setting it to encrypted=true
#   name              = "Encrypted copy of ${data.aws_ami.ami.name}"
#   description       = "A copy of ${data.aws_ami.ami.name} to enable root disk encryption"
#   source_ami_id     = data.aws_ami.ami.image_id
#   source_ami_region = var.ghes_region
#   encrypted         = true

#   tags = merge(
#     map("Name", format("%s-encrypted", var.name)),
#     var.tags
#   )
# }

resource "aws_instance" "ghes" {
  count = length(var.ghes_azs) > 0 ? length(var.ghes_azs) : 0

  # ami                    = aws_ami_copy.ami_encrypted.id
  ami                    = data.aws_ami.ami.image_id
  instance_type          = var.ghes_instance_type
  vpc_security_group_ids = [aws_security_group.security_group.id]
  availability_zone      = element(var.ghes_azs, count.index)
  key_name               = aws_key_pair.key_pair.key_name
  source_dest_check      = false

  disable_api_termination = terraform.workspace == "development" ? false : true

  root_block_device {
    volume_size           = local.root_volumn_size
    volume_type           = var.ghes_data_volume_type
    iops                  = local.iops
    delete_on_termination = true
  }

  ebs_block_device {
    device_name           = "/dev/sdb"
    volume_size           = local.data_volume_size
    volume_type           = var.ghes_data_volume_type
    iops                  = local.iops
    encrypted             = true
    delete_on_termination = terraform.workspace == "development" ? true : false
  }

  tags = merge(
    map("Name", format("%s-%d", var.name, count.index + 1)),
    var.tags
  )

  volume_tags = merge(
    map("Name", format("%s-%d", var.name, count.index + 1)),
    var.tags
  )
}

resource "aws_eip" "ghes_eip" {
  count = terraform.workspace == "development" ? 0 : (
    length(var.ghes_azs) > 0 ? length(var.ghes_azs) : 0
  )

  instance = element(aws_instance.ghes.*.id, count.index)
  vpc      = true

  tags = merge(
    map("Name", format("%s-%d-eip", var.name, count.index + 1)),
    var.tags
  )
}
