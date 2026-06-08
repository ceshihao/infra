# Minimal skeleton equivalent to provider-aws/alb.tf:
#   AWS aws_lb (ALB)             -> alicloud_alb_load_balancer
#   AWS aws_lb_listener (80/443) -> alicloud_alb_listener
#   AWS aws_lb_target_group      -> alicloud_alb_server_group
#   AWS aws_lb_listener_rule     -> alicloud_alb_rule
#
# Key differences:
#   1. ALB must be bound to at least 2 vswitches in different AZs
#   2. HTTPS certificate must be uploaded to CAS (Certificate Authority Service) first, referenced via server_certificate.certificate_id
#      This skeleton uses var.alicloud_acm_certificate_id, which must be provided externally from CAS
#   3. ALB does not support protocol_version="GRPC"; gRPC listener requires listener_protocol="HTTPS" + server_group_protocol="GRPC"
#   4. access_logs delivery to OSS requires enabling log delivery in the ALB console; skeleton only declares the bucket, does not force enable
resource "alicloud_alb_load_balancer" "ingress" {
  load_balancer_name    = "${var.prefix}ingress"
  load_balancer_edition = "Standard"
  vpc_id                = module.init.vpc_id
  address_type          = "Internet"
  address_allocated_mode = "Dynamic"

  # ALB requires at least 2 AZs
  dynamic "zone_mappings" {
    for_each = slice(module.init.vpc_public_subnet_ids, 0, min(3, length(module.init.vpc_public_subnet_ids)))
    content {
      vswitch_id = zone_mappings.value
      # zone_id is auto-inferred by AlibabaCloud based on vswitch
    }
  }

  load_balancer_billing_config {
    pay_type = "PostPay"
  }

  modification_protection_config {
    status = "NonProtection"
  }

  tags = {
    Name = "${var.prefix}ingress"
  }
}

# HTTP -> HTTPS redirect
resource "alicloud_alb_listener" "ingress_redirect" {
  load_balancer_id     = alicloud_alb_load_balancer.ingress.id
  listener_protocol    = "HTTP"
  listener_port        = 80
  listener_description = "${var.prefix}ingress-redirect"

  default_actions {
    type = "Redirect"
    redirect_config {
      protocol    = "HTTPS"
      port        = "443"
      http_code   = "301"
      host        = "$${host}"
      path        = "$${path}"
      query       = "$${query}"
    }
  }
}

# HTTPS main listener
resource "alicloud_alb_listener" "ingress_wildcard" {
  load_balancer_id     = alicloud_alb_load_balancer.ingress.id
  listener_protocol    = "HTTPS"
  listener_port        = 443
  listener_description = "${var.prefix}ingress-wildcard"

  certificates {
    certificate_id = var.alicloud_acm_certificate_id
  }

  default_actions {
    type = "ForwardGroup"
    forward_group_config {
      server_group_tuples {
        server_group_id = alicloud_alb_server_group.ingress.id
      }
    }
  }
}

# gRPC route: dispatch to grpc server group based on content-type header (lower priority value matches first)
resource "alicloud_alb_rule" "ingress_grpc" {
  rule_name    = "${var.prefix}ingress-grpc"
  listener_id  = alicloud_alb_listener.ingress_wildcard.id
  priority     = 20

  rule_conditions {
    type = "Header"
    header_config {
      key    = "content-type"
      values = ["application/grpc*"]
    }
  }

  rule_actions {
    type  = "ForwardGroup"
    order = 1
    forward_group_config {
      server_group_tuples {
        server_group_id = alicloud_alb_server_group.ingress_grpc.id
      }
    }
  }
}

# Nomad UI/API route: match by host header nomad.${domain}
resource "alicloud_alb_rule" "nomad" {
  rule_name   = "${var.prefix}nomad"
  listener_id = alicloud_alb_listener.ingress_wildcard.id
  priority    = 10

  rule_conditions {
    type = "Host"
    host_config {
      values = ["nomad.${var.domain_name}"]
    }
  }

  rule_actions {
    type  = "ForwardGroup"
    order = 1
    forward_group_config {
      server_group_tuples {
        server_group_id = alicloud_alb_server_group.nomad.id
      }
    }
  }
}

resource "alicloud_alb_server_group" "ingress" {
  server_group_name = "${var.prefix}ingress"
  vpc_id            = module.init.vpc_id
  protocol          = "HTTP"
  scheduler         = "Wrr"
  server_group_type = "Instance"

  health_check_config {
    health_check_enabled  = true
    health_check_path     = "/ping"
    health_check_protocol = "HTTP"
    health_check_codes    = ["http_2xx"]
    health_check_interval = 5
    health_check_timeout  = 2
    healthy_threshold     = 2
    unhealthy_threshold   = 2
  }
}

resource "alicloud_alb_server_group" "ingress_grpc" {
  server_group_name = "${var.prefix}ingress-grpc"
  vpc_id            = module.init.vpc_id
  protocol          = "GRPC"
  scheduler         = "Wrr"
  server_group_type = "Instance"

  health_check_config {
    health_check_enabled  = true
    health_check_path     = "/ping"
    health_check_protocol = "HTTP"
    health_check_codes    = ["http_2xx"]
    health_check_interval = 5
    health_check_timeout  = 2
    healthy_threshold     = 2
    unhealthy_threshold   = 2
  }
}

resource "alicloud_alb_server_group" "nomad" {
  server_group_name = "${var.prefix}nomad"
  vpc_id            = module.init.vpc_id
  protocol          = "HTTP"
  scheduler         = "Wrr"
  server_group_type = "Instance"

  health_check_config {
    health_check_enabled  = true
    health_check_path     = "/v1/status/peers"
    health_check_protocol = "HTTP"
    health_check_codes    = ["http_2xx"]
    health_check_interval = 5
    health_check_timeout  = 2
    healthy_threshold     = 2
    unhealthy_threshold   = 2
  }
}
