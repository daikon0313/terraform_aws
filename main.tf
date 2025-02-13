terraform {
    required_providers {
        aws = {
        source  = "hashicorp/aws"
        version = "~> 5.0"
        }
    }
}

provider "aws" {
  region  = "ap-northeast-1"
}

############################################
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "tf-harato-test-main-vpc"
  }
}

# パブリックサブネット1作成
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1a"

  tags = {
    Name = "tf-harato-test-public-subnet-1"
  }
}

# パブリックサブネット2作成
resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1c"

  tags = {
    Name = "tf-harato-test-public-subnet-2"
  }
}

# インターネットゲートウェイ作成
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "tf-harato-test-main-igw"
  }
}

# ルートテーブル作成 (パブリックルート)
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "tf-harato-test-public-route-table"
  }
}

# サブネット1とルートテーブルを関連付ける
resource "aws_route_table_association" "public_association_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

# サブネット2とルートテーブルを関連付ける
resource "aws_route_table_association" "public_association_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

# セキュリティグループ作成 (HTTPおよびSSHアクセスを許可)
resource "aws_security_group" "public_sg" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tf-harato-test-public-sg"
  }
}

# アプリケーションロードバランサー(ALB)作成
resource "aws_lb" "main_alb" {
  name               = "tf-harato-test-main-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

  enable_deletion_protection = false

  tags = {
    Name = "tf-harato-test-main-alb"
  }
}

# ターゲットグループ作成 (EC2インスタンスをターゲットに)
resource "aws_lb_target_group" "main_target_group" {
  name     = "tf-harato-test-main-target-gp"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main_vpc.id

  health_check {
    interval = 30
    path     = "/"
    protocol = "HTTP"
    timeout  = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "tf-harato-test-main-target-group"
  }
}

# EC2インスタンス1をターゲットグループに追加
resource "aws_lb_target_group_attachment" "ec2_attachment_1" {
  target_group_arn = aws_lb_target_group.main_target_group.arn
  target_id        = aws_instance.apache_ec2_1.id
  port             = 80
}

# EC2インスタンス2をターゲットグループに追加
resource "aws_lb_target_group_attachment" "ec2_attachment_2" {
  target_group_arn = aws_lb_target_group.main_target_group.arn
  target_id        = aws_instance.apache_ec2_2.id
  port             = 80
}

resource "aws_key_pair" "tf_harato_key" {
  key_name   = "tf-harato-key"
  public_key = file("./key/harato-test-cog.pub")  # 既存の公開鍵を指定
}

resource "aws_instance" "apache_ec2_1" {
  ami                         = "ami-0b6fe957a0eb4c1b9"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet_1.id
  security_groups             = [aws_security_group.public_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.tf_harato_key.key_name

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install -y httpd amazon-ssm-agent
    sudo systemctl start httpd
    sudo systemctl enable httpd
    sudo systemctl start amazon-ssm-agent
    sudo systemctl enable amazon-ssm-agent
    echo "<html><body><h1>Aサイト</h1></body></html>" > /var/www/html/index.html
  EOF

  tags = {
    Name = "tf-harato-test-apache-ec2-1"
  }
}

resource "aws_instance" "apache_ec2_2" {
  ami                         = "ami-0b6fe957a0eb4c1b9"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet_2.id
  security_groups             = [aws_security_group.public_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.tf_harato_key.key_name

  user_data = <<-EOF
  #!/bin/bash
    sudo yum update -y
    sudo yum install -y httpd amazon-ssm-agent
    sudo systemctl start httpd
    sudo systemctl enable httpd
    sudo systemctl start amazon-ssm-agent
    sudo systemctl enable amazon-ssm-agent
    echo "<html><body><h1>Bサイト</h1></body></html>" > /var/www/html/index.html
  EOF

  tags = {
    Name = "tf-harato-test-apache-ec2-2"
  }
}

output "alb_dns_name" {
  value = aws_lb.main_alb.dns_name
}

# ALBのリスナー作成 (HTTPリスナー)
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.main_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main_target_group.arn
  }
}
