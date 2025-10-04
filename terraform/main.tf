terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "app_sg" {
  name        = "ci-cd-demo-sg"
  description = "Security group for CI/CD demo app"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "ci-cd-demo-sg"
  }
}

resource "aws_ecr_repository" "app_repo" {
  name                 = "ci-cd-demo-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "ci-cd-demo-repo"
  }
}

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

  tags = {
    Name = "ci-cd-demo-ec2-role"
  }
}

resource "aws_iam_role_policy" "ec2_ecr_policy" {
  name = "ci-cd-demo-ecr-policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ci-cd-demo-ec2-profile"
  role = aws_iam_role.ec2_role.name

  tags = {
    Name = "ci-cd-demo-ec2-profile"
  }
}

resource "aws_instance" "app_instance" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  key_name               = var.key_name != "" ? var.key_name : null
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  subnet_id              = tolist(data.aws_subnets.default.ids)[0]

  user_data = templatefile("${path.module}/user_data.sh", {
    aws_region         = var.aws_region
    ecr_repository_url = aws_ecr_repository.app_repo.repository_url
  })

  user_data_replace_on_change = true

  tags = {
    Name = "ci-cd-demo-instance"
  }

  depends_on = [
    aws_iam_role_policy.ec2_ecr_policy
  ]
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app_repo.repository_url
}

output "ec2_public_ip" {
  description = "EC2 instance public IP"
  value       = aws_instance.app_instance.public_ip
}

output "app_url" {
  description = "Application URL"
  value       = "http://${aws_instance.app_instance.public_ip}"
}
