##############################
# terraform/phase1-eks/main.tf (UPDATED)
##############################

# 1) AWS Provider
provider "aws" {
  region = var.region
}

# 2) Custom VPC
resource "aws_vpc" "eks" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

# 3) Public subnets (one per AZ)
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.eks.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-public-${count.index}"
    Type = "public"
  }
}

# 3a) Private subnets (one per AZ)
resource "aws_subnet" "private" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.eks.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.cluster_name}-private-${count.index}"
    Type = "private"
  }
}

# 4) Internet Gateway + Public Route Table
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.eks.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# 4a) Allocate Elastic IPs for NAT
resource "aws_eip" "nat" {
  count = length(aws_subnet.public)
  domain = "vpc"
}

# 4b) NAT Gateways in each AZ (for private subnet Internet egress)
resource "aws_nat_gateway" "nat" {
  count         = length(aws_subnet.public)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.cluster_name}-nat-${count.index}"
  }
}

# 4c) Private Route Tables using NAT
resource "aws_route_table" "private_rt" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.eks.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt-${count.index}"
  }
}

resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_rt[count.index].id
}

# 5) IAM Role for EKS control plane (unchanged)
data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    actions    = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster_role" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# 6) EKS Control Plane, now spanning both subnet types
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    # include *both* public and private subnets for control-plane ENIs
    subnet_ids = concat(
      aws_subnet.public[*].id,
      aws_subnet.private[*].id
    )
  }
}

# 7) IAM Role for worker nodes + required policies (unchanged)
data "aws_iam_policy_document" "node_assume_role" {
  statement {
    actions    = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node_role" {
  name               = "${var.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_readonly" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# 8) Managed node group in private subnets for improved isolation
resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-workers"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.private[*].id

  scaling_config {
    desired_size = var.node_count
    min_size     = var.min_node_count
    max_size     = var.max_node_count
  }

  instance_types = [var.instance_type]
}

##############################
# 9) Bastion Host for SSH access (unchanged)
##############################
data "aws_iam_role" "eks_client_role" {
  name = "EKS_Client"
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "${var.cluster_name}-bastion-profile"
  role = data.aws_iam_role.eks_client_role.name
}

data "aws_ami" "amazon_linux2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_security_group" "bastion_sg" {
  name        = "${var.cluster_name}-bastion-sg"
  description = "Allow SSH from anywhere"
  vpc_id      = aws_vpc.eks.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux2.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  key_name                    = var.bastion_key_name
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]

  iam_instance_profile = aws_iam_instance_profile.bastion_profile.name

  tags = {
    Name = "${var.cluster_name}-bastion"
  }
}

# Output the bastion IP for SSH access
output "bastion_public_ip" {
  description = "Public IP of the SSH bastion host"
  value       = aws_instance.bastion.public_ip
}

##########################
# Fetch the EKS VPC and public subnets
##########################

data "aws_vpc" "eks" {
  id = aws_vpc.eks.id
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.eks.id]
  }
  filter {
    name   = "tag:Type"
    values = ["public"]
  }
}