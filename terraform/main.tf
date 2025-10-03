terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.0.0"
    }
  }
}

# Configure the AWS provider
provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# ECR Repository for Docker images
resource "aws_ecr_repository" "app_repo" {
  name                 = "ci-cd-demo-repo"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

# IAM Role for EC2 to access ECR
resource "aws_iam_role" "ec2_role" {
  name = "ci-cd-demo-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_ecr_policy" {
  name = "ci-cd-demo-ecr-policy"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ci-cd-demo-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# EC2 Instance to run the app
resource "aws_instance" "app_instance" {
  ami           = "ami-0e86e20dae9224db8"  # Amazon Linux 2 AMI (us-east-1; update for your region)
  instance_type = "t3.micro"  # Changed to t3.micro (verify free-tier eligibility)
  key_name      = var.key_name
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo amazon-linux-extras install docker -y
    sudo service docker start
    sudo usermod -a -G docker ec2-user
    aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.app_repo.repository_url}
    docker pull ${aws_ecr_repository.app_repo.repository_url}:latest
    docker run -d -p 80:5000 ${aws_ecr_repository.app_repo.repository_url}:latest
  EOF

  tags = {
    Name = "ci-cd-demo-instance"
  }
}

# Output ECR URL
output "ecr_repository_url" {
  value = aws_ecr_repository.app_repo.repository_url
}

# Output EC2 Public IP
output "ec2_public_ip" {
  value = aws_instance.app_instance.public_ip
}