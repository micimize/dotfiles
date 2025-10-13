# A Terraform configuration to provision the AWS infrastructure for a Btrfs backup target.
# This single file defines a complete and reproducible environment.

provider "aws" {
  region = var.aws_region
}

# --- Variables ---
# Define user-configurable variables.

variable "aws_region" {
  description = "The AWS region to deploy resources to."
  type        = string
  default     = "us-west-1" # close to sf
}

variable "ssh_public_key" {
  description = "The public key for SSH authentication. This key will be added to the dedicated btrbk user on the EC2 instance."
  type        = string
}

variable "key_pair_name" {
  description = "The name for the AWS key pair. This is used for SSH access."
  type        = string
  default     = "btrfs-sync-ssh-key"
}

variable "ebs_volume_size" {
  description = "Size of the backup EBS volume in GiB"
  type        = number
  default     = 100
}

# --- Data Sources ---
# Use a data source to automatically fetch the most recent Ubuntu 22.04 LTS AMI.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's AWS account ID
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# --- Resources ---

# 1. Create a security group to control network access.
# This security group only allows inbound SSH traffic from any IP.
resource "aws_security_group" "btrbk_sg" {
  name        = "btrbk_sg"
  description = "Allow inbound SSH (port 22) traffic from a known source for btrbk backups"

  # Ingress rule to allow SSH from any IP.
  ingress {
    description = "Allow SSH from any IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress rules to allow outbound traffic for system updates.
  egress {
    description = "Allow HTTPS outbound for package manager updates"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow HTTP outbound for package manager updates"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "btrbk_security_group"
  }
}

# 2. Create an SSH key pair in AWS.
# The public key is used to authenticate with the EC2 instance.
resource "aws_key_pair" "btrbk_key" {
  key_name   = var.key_pair_name
  public_key = var.ssh_public_key
}

# 3. Create the EC2 instance that will serve as the backup target.
resource "aws_instance" "btrbk_backup_target" {
  ami           = data.aws_ami.ubuntu.id # Use the dynamically fetched AMI ID.
  instance_type = "t3a.nano" # A minimal, cost-effective instance type for a backup target.
  key_name      = aws_key_pair.btrbk_key.key_name
  vpc_security_group_ids = [aws_security_group.btrbk_sg.id]

  # Use user_data from external file for better maintainability and debugging.
  # The file contains setup logic for btrfs, btrbk user, and SSH configuration.
  # NOTE: The key_name above also adds the SSH key to the default ubuntu user,
  # which is useful for debugging if the btrbk user setup fails.
  user_data = templatefile("${path.module}/user-data.sh", {
    ssh_authorized_keys_entry = "command=\"/usr/local/bin/btrbk-ssh\" ${var.ssh_public_key}"
  })

  tags = {
    Name = "btrbk_backup_target"
  }
}

# 4. Create an encrypted EBS volume to store the backups.
resource "aws_ebs_volume" "btrbk_volume" {
  size              = var.ebs_volume_size
  encrypted         = true
  # The availability zone must match the EC2 instance's zone.
  availability_zone = aws_instance.btrbk_backup_target.availability_zone

  tags = {
    Name = "btrbk_backup_volume"
  }
}

# 5. Attach the encrypted EBS volume to the EC2 instance.
resource "aws_volume_attachment" "btrbk_attach" {
  # The device name on the EC2 instance
  device_name = "/dev/sdh" 
  volume_id   = aws_ebs_volume.btrbk_volume.id
  instance_id = aws_instance.btrbk_backup_target.id
}

# --- Outputs ---

# Output the public IP address of the EC2 instance for easy access.
output "instance_public_ip" {
  description = "The public IP address of the btrbk backup target."
  value       = aws_instance.btrbk_backup_target.public_ip
}

# Output the SSH connection string for easy access
output "ssh_connection_string" {
  description = "SSH connection string for the btrbk user"
  value       = "btrbk@${aws_instance.btrbk_backup_target.public_ip}"
}

# Output the backup target path for btrbk configuration
output "backup_target_path" {
  description = "Path on remote server for backups"
  value       = "/backup_volume/backups"
}

# Output the full btrbk target string
output "btrbk_target" {
  description = "Full target string for btrbk configuration"
  value       = "ssh://btrbk@${aws_instance.btrbk_backup_target.public_ip}/backup_volume/backups/"
}

# Output instance ID for troubleshooting
output "instance_id" {
  description = "EC2 instance ID for AWS console access"
  value       = aws_instance.btrbk_backup_target.id
}

# Output volume ID for troubleshooting
output "volume_id" {
  description = "EBS volume ID for AWS console access"
  value       = aws_ebs_volume.btrbk_volume.id
}
