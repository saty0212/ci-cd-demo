#!/bin/bash
set -e

# Log everything to a file for debugging
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting user data script..."

# Update system
yum update -y

# Install Docker
yum install -y docker

# Start Docker service
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Wait for Docker to be fully ready
sleep 5

# Login to ECR
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_repository_url}

# Pull and run the Docker container
# Add retry logic in case image isn't immediately available
for i in {1..5}; do
  if docker pull ${ecr_repository_url}:latest; then
    echo "Successfully pulled Docker image"
    break
  else
    echo "Attempt $i: Failed to pull image, retrying in 30 seconds..."
    sleep 30
  fi
done

# Stop any existing container
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true

# Run the container
docker run -d --restart unless-stopped -p 80:5000 --name app ${ecr_repository_url}:latest

echo "User data script completed successfully!"
