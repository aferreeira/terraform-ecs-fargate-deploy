resource "aws_cloudwatch_log_group" "cw-log-group" {
  name = "${var.repository_name}"

  tags {
    Environment = "${var.environment}"
    Application = "${var.repository_name}"
  }
}

resource "aws_ecr_repository" "app-repo" {
  name = "${var.repository_name}"
}

resource "aws_ecs_cluster" "cluster" {
  name = "${var.environment}-ecs-cluster"
}

data "template_file" "app_task" {
  template = "${file("${path.module}/tasks/app_task_definition.json")}"

  vars {
    image           = "${aws_ecr_repository.app-repo.repository_url}"
    log_group       = "${aws_cloudwatch_log_group.cw-log-group.name}"
    app_name        = "${var.repository_name}"
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.repository_name}-task-family"
  container_definitions    = "${data.template_file.app_task.rendered}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "2048"
  memory                   = "4096"
  execution_role_arn       = "${aws_iam_role.ecs-execution-role.arn}"
  task_role_arn            = "${aws_iam_role.ecs-execution-role.arn}"
  depends_on               = ["aws_iam_role.ecs-execution-role"]
}

resource "random_id" "random-id" {
  byte_length = 2
}

resource "aws_alb_target_group" "alb-target-group" {
  name     = "${var.environment}-alb-target-group-${random_id.random-id.hex}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${var.vpc_id}"
  target_type = "ip"

  health_check {
    healthy_threshold   = "5"
    unhealthy_threshold = "2"
    interval            = "30"
    matcher             = "200"
    path                = "/health"
    port                = "80"
    protocol            = "HTTP"
    timeout             = "5"
  }

  lifecycle {
    create_before_destroy = true
  }
  depends_on = ["aws_alb.alb"]
}

resource "aws_security_group" "web-inbound-sg" {
  name        = "${var.environment}-web-inbound-sg"
  description = "Allow HTTP from Anywhere into ALB"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.environment}-web-inbound-sg"
  }
}

resource "aws_alb" "alb" {
  name            = "${var.environment}-alb-${var.repository_name}"
  subnets         = ["${var.public_subnet_ids}"]
  security_groups = ["${var.security_groups_ids}", "${aws_security_group.web-inbound-sg.id}"]

  tags {
    Name        = "${var.environment}-alb-${var.repository_name}"
    Environment = "${var.environment}"
  }
}

resource "aws_alb_listener" "alb-listener" {
  load_balancer_arn = "${aws_alb.alb.arn}"
  port              = "80"
  protocol          = "HTTP"
  depends_on        = ["aws_alb_target_group.alb-target-group", "aws_alb.alb"]

  default_action {
    target_group_arn = "${aws_alb_target_group.alb-target-group.arn}"
    type             = "forward"
  }
}

data "aws_iam_policy_document" "ecs-service-role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs-role" {
  name               = "ecs-role"
  assume_role_policy = "${data.aws_iam_policy_document.ecs-service-role.json}"
}

data "aws_iam_policy_document" "ecs-service-policy" {
  statement {
    effect = "Allow"
    resources = ["*"]
    actions = [
      "elasticloadbalancing:Describe*",
      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      "ec2:Describe*",
      "ec2:AuthorizeSecurityGroupIngress"
    ]
  }
}

resource "aws_iam_role_policy" "ecs-service-role-policy" {
  name   = "ecs-service-role-policy"
  policy = "${data.aws_iam_policy_document.ecs-service-policy.json}"
  role   = "${aws_iam_role.ecs-role.id}"
}

resource "aws_iam_role" "ecs-execution-role" {
  name               = "ecs_task_execution_role"
  assume_role_policy = "${file("${path.module}/policies/ecs-task-execution-role.json")}"
}

resource "aws_iam_role_policy" "ecs-execution-role-policy" {
  name       = "ecs-execution-role-policy"
  policy     = "${file("${path.module}/policies/ecs-execution-role-policy.json")}"
  role       = "${aws_iam_role.ecs-execution-role.id}"
  depends_on = ["aws_iam_role.ecs-execution-role"]
}

resource "aws_security_group" "ecs-service" {
  vpc_id      = "${var.vpc_id}"
  name        = "${var.environment}-ecs-service-sg"
  description = "Allow egress from container"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name        = "${var.environment}-ecs-service-sg"
    Environment = "${var.environment}"
  }
}

data "aws_ecs_task_definition" "app" {
  task_definition = "${aws_ecs_task_definition.app.family}"

  depends_on      = ["aws_ecs_task_definition.app"]
}

resource "aws_ecs_service" "app" {
  name            = "${var.repository_name}-svc"
  task_definition = "${aws_ecs_task_definition.app.family}:${max("${aws_ecs_task_definition.app.revision}", "${data.aws_ecs_task_definition.app.revision}")}"
  desired_count   = 1
  launch_type     = "FARGATE"
  cluster         = "${aws_ecs_cluster.cluster.id}"
  depends_on      = ["aws_iam_role_policy.ecs-service-role-policy", "aws_alb_target_group.alb-target-group", "aws_ecs_task_definition.app"]

  network_configuration {
    security_groups = ["${var.security_groups_ids}", "${aws_security_group.ecs-service.id}"]
    subnets         = ["${var.subnets_ids}"]
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.alb-target-group.arn}"
    container_name   = "${var.repository_name}"
    container_port   = "80"
  }

}

resource "aws_iam_role" "ecs-autoscale-role" {
  name               = "${var.environment}-ecs-autoscale-role"
  assume_role_policy = "${file("${path.module}/policies/ecs-autoscale-role.json")}"
}

resource "aws_iam_role_policy" "ecs-autoscale-role-policy" {
  name   = "ecs-autoscale-role-policy"
  policy = "${file("${path.module}/policies/ecs-autoscale-role-policy.json")}"
  role   = "${aws_iam_role.ecs-autoscale-role.id}"
}

resource "aws_appautoscaling_target" "target" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  role_arn           = "${aws_iam_role.ecs-autoscale-role.arn}"
  min_capacity       = 2
  max_capacity       = 4
}

resource "aws_appautoscaling_policy" "up" {
  name                    = "${var.environment}-scale-up"
  service_namespace       = "ecs"
  resource_id             = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.app.name}"
  scalable_dimension      = "ecs:service:DesiredCount"


  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment = 1
    }
  }

  depends_on = ["aws_appautoscaling_target.target"]
}

resource "aws_appautoscaling_policy" "down" {
  name                    = "${var.environment}-scale-down"
  service_namespace       = "ecs"
  resource_id             = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.app.name}"
  scalable_dimension      = "ecs:service:DesiredCount"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment = -1
    }
  }

  depends_on = ["aws_appautoscaling_target.target"]
}

resource "aws_cloudwatch_metric_alarm" "service-cpu-high" {
  alarm_name          = "${var.environment}-${var.repository_name}-cpu-utilization-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "85"

  dimensions {
    ClusterName = "${aws_ecs_cluster.cluster.name}"
    ServiceName = "${aws_ecs_service.app.name}"
  }

  alarm_actions = ["${aws_appautoscaling_policy.up.arn}"]
  ok_actions    = ["${aws_appautoscaling_policy.down.arn}"]
}
