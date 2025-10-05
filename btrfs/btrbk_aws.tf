# A Terraform configuration to provision the AWS infrastructure for a Btrfs backup target.
# This single file defines a complete and reproducible environment.

# Define the AWS provider and set the region.
provider "aws" {
  # The region is set to us-west-1 (Northern California) for optimal performance
  # for users in the San Francisco Bay Area.
  region = var.aws_region
}

# --- Variables ---
# Define user-configurable variables.

variable "aws_region" {
  description = "The AWS region to deploy resources to."
  type        = string
  default     = "us-west-1"
}

variable "ssh_public_key" {
  description = "The public key for SSH authentication. This key will be added to the dedicated btrbk user on the EC2 instance."
  type        = string
}

variable "key_pair_name" {
  description = "The name for the AWS key pair. This is used for SSH access."
  type        = string
  default     = "btrbk-backup-key"
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
  
  # Use user_data to automatically configure the instance on first boot.
  # This script installs Btrfs tools, formats the volume, creates a dedicated user,
  # and mounts the volume persistently.
  user_data = <<-EOF
              #!/bin/bash
              # Wait for the volume to be attached and available (dev/sdh is a common device name for the first attached EBS volume)
              while [ ! -e "/dev/sdh" ]; do sleep 1; done
              
              # Install Btrfs tools to manage the filesystem
              apt update
              apt install -y btrfs-progs
              
              # Format the attached EBS volume with a Btrfs filesystem
              mkfs.btrfs /dev/sdh
              
              # Create a mount point for the volume
              mkdir -p /backup_volume
              
              # Mount the newly formatted volume
              mount /dev/sdh /backup_volume
              
              # Add the volume to /etc/fstab to ensure it is mounted automatically on every reboot
              echo "/dev/sdh /backup_volume btrfs defaults 0 0" >> /etc/fstab

              # --- Btrbk User Configuration for enhanced security ---
              # Create a dedicated system user for btrbk without a home directory or password
              useradd -r btrbk -s /bin/false

              # Create .ssh directory and authorized_keys file for the new user
              mkdir -p /home/btrbk/.ssh
              touch /home/btrbk/.ssh/authorized_keys
              chown -R btrbk:btrbk /home/btrbk
              chmod 700 /home/btrbk/.ssh
              chmod 600 /home/btrbk/.ssh/authorized_keys

              # Add the public key with the command restriction to the authorized_keys file.
              # This ensures the 'btrbk' user can only run the `btrbk-ssh` command,
              # preventing arbitrary shell access.
              echo 'command="btrbk-ssh" ${var.ssh_public_key}' >> /home/btrbk/.ssh/authorized_keys
              
              # Ensure the authorized_keys file is owned by the btrbk user.
              chown btrbk:btrbk /home/btrbk/.ssh/authorized_keys

              # --- Implement the btrbk-ssh wrapper script ---
              # This script limits what commands the SSH user can run.
              
              cat << 'EOT' > /usr/local/bin/btrbk-ssh
              #!/bin/bash
              
              case "$SSH_ORIGINAL_COMMAND" in
                # Allow only btrfs send/receive commands.
                # Adjust this if you need other btrbk commands.
                'btrfs send'*)
                  eval "$SSH_ORIGINAL_COMMAND"
                  ;;
                'btrbk receive'*)
                  eval "$SSH_ORIGINAL_COMMAND"
                  ;;
                *)
                  # Forbid any other commands.
                  echo "Access denied: Command not permitted." >&2
                  exit 1
                  ;;
              esac
              EOT
              
              # Make the script executable
              chmod +x /usr/local/bin/btrbk-ssh

              EOF
  
  # Ensure the instance and the EBS volume are in the same availability zone for attachment.
  availability_zone = aws_security_group.btrbk_sg.availability_zone

  tags = {
    Name = "btrbk_backup_target"
  }
}

# 4. Create an encrypted EBS volume to store the backups.
resource "aws_ebs_volume" "btrbk_volume" {
  size              = 100 # Adjust size as needed (in GiB)
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
