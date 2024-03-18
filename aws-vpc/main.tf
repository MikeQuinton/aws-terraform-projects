data "aws_caller_identity" "current" {}

locals {
    account_id = data.aws_caller_identity.current.account_id
}

output "account_id" {
  value = local.account_id
}

/*
VPC creation... default network ACL and Route table also created... already associated with existing DHCP set
Exists across all AZ in a region
*/

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "Main VPC"
  }
}

# Public subnets, spanning across all 3 AZ's
resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.public_subnet_cidrs, count.index)
  availability_zone = element(var.azs, count.index)

  tags = {
    Name = "Public Subnet ${count.index + 1}"
  }
}

# Private subnets, spanning across all 3 AZ's
resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(var.azs, count.index)

  tags = {
    Name = "Private Subnet ${count.index + 1}"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "Main VPC IG"
  }
}

# Route table, external access to public subnets
resource "aws_route_table" "second_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "2nd Route Table"
  }
}

resource "aws_route_table_association" "public_subnet_asso" {
  count = length(var.public_subnet_cidrs)
  subnet_id = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = aws_route_table.second_rt.id
}

resource "aws_eip" "nat_eip" {
  count = var.eip_count
  tags = {
    Name = "EIP-${count.index}"
  }
}

resource "aws_nat_gateway" "nat" {
  count = length(var.private_subnet_cidrs)
  allocation_id = element(aws_eip.nat_eip[*].id, count.index)
  subnet_id = element(aws_subnet.private_subnets[*].id, count.index)

  tags = {
    Name = "NAT-${count.index}"
  }
}

resource "aws_cloudwatch_log_group" "vpc-main-flow-logs" {
  name              = "FlowLogsGroup"
  retention_in_days = 30  // Optional: Set the retention period for log events, in days
}

resource "aws_flow_log" "vpc_flow_log" {
  depends_on = [aws_vpc.main]
  vpc_id = aws_vpc.main.id
  log_destination = "arn:aws:logs:eu-west-1:${local.account_id}:log-group:FlowLogsGroup"
  traffic_type ="ALL"

  log_format = "json"
  max_aggregation_interval = 60

  tags = {
    Name = "vpc-main-flow-log"
  }
}