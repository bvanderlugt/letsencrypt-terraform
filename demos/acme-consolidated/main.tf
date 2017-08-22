# The Let's Encrypt registration process has been included to help demo
# a single end-to-end process, however this would normally be split into
# two. See demos/acme-part-1-registration and demos/acme-part-2-core
# for an example of how this might be split

provider "aws" {
  region = "${var.demo_acme_challenge_aws_region}"
}

module "acme-reg" {
    source = "../../modules/acme-account-registration"
    acme_server_url               = "${var.demo_acme_server_url}"
    acme_registration_email       = "${var.demo_acme_registration_email}"
}

# module "dns" {
#     source = "../../modules/dns/direct"
#     dns_domain_name               = "${var.demo_domain_name}"
#     dns_domain_subdomain          = "letsencrypt-test"
#     dns_cname_value               = "${"aws_elb.web.dns_name"}"
# }

module "acme-cert" {
    source = "../../modules/acme-cert-request"
    acme_server_url                 = "${var.demo_acme_server_url}"
    acme_account_registration_url   = "${module.acme-reg.registration_url}"
    acme_account_key_pem            = "${module.acme-reg.registration_private_key_pem}"
    # acme_certificate_common_name    = "${module.dns.fqdn_domain_name}"
    # acme_certificate_common_name = "${aws_route53_record.letsencrypt-terraform.fqdn}"
    acme_certificate_common_name    = "${var.demo_domain_name}"
    acme_certificate_subject_alt_names = "${var.demo_subject_alternative_names}"
    # To make use of a single direct DNS record, comment out the line
    # above, uncomment the one below, and ensure the dns module source
    # is loaded from modules/dns/direct. This current approach has been
    # done to remove a cyclic dependency.
    # acme_certificate_common_name  = "${var.demo_domain_name}.${var.demo_domain_subdomain}"

    acme_challenge_aws_access_key_id     = "${var.demo_acme_challenge_aws_access_key_id}"
    acme_challenge_aws_secret_access_key = "${var.demo_acme_challenge_aws_secret_access_key}"
    acme_challenge_aws_region            = "${var.demo_acme_challenge_aws_region}"
}

##### End goal is to have certs uploaded here #####
resource "aws_iam_server_certificate" "elb_cert" {
  name_prefix       = "testme-multi-"
  certificate_body  = "${module.acme-cert.certificate_pem}"
  certificate_chain = "${module.acme-cert.certificate_issuer_pem}"
  private_key       = "${module.acme-cert.certificate_private_key_pem}"

  lifecycle {
    create_before_destroy = true
  }
}


##### Route53 CNAME records to map to ELB #####
data "aws_route53_zone" "main" {
  name         = "${var.demo_domain_name}"
  private_zone = false
}

##### does the output of a count-based resource guarantee the same order as the input list? #####
resource "aws_route53_record" "letsencrypt-terraform" {
   count = "${length(var.demo_subject_alternative_names)}"
   zone_id = "${data.aws_route53_zone.main.zone_id}"
   name    = "${var.demo_subject_alternative_names[count.index]}"
   type    = "CNAME"
   ttl     = "60"
   records = ["${aws_elb.web.*.dns_name[count.index]}"]
}

##### If we want to attach certs to elb at runtime we need to do the following things #####
resource "aws_elb" "web" {
  count = "${length(var.demo_subject_alternative_names)}"
  name = "${join("-", split(".", var.demo_subject_alternative_names[count.index]))}"

  subnets         = ["${aws_subnet.public.id}"]
  security_groups = ["${aws_security_group.elb.id}"]

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "${aws_iam_server_certificate.elb_cert.arn}"

  }

  tags {
    Name    = "letfdemo-elb"
    Purpose = "letfdemo"
  }
}

##### Dependencies for creating an ELB #####
resource "aws_subnet" "public" {
  vpc_id                  = "${aws_vpc.demovpc.id}"
  cidr_block              = "10.20.100.32/27"
  map_public_ip_on_launch = true

  tags {
    Name = "letfdemo-subnet"
    Purpose = "letfdemo"
  }
}

resource "aws_security_group" "elb" {
  name        = "letfdemo-sg-elb"
  description = "ELB security group"
  vpc_id      = "${aws_vpc.demovpc.id}"

  # HTTPS access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "letfdemo-sg-elb"
    Purpose = "letfdemo"
  }
}

resource "aws_vpc" "demovpc" {
  cidr_block = "10.20.100.0/24"
  enable_dns_hostnames = true

  tags {
    Name    = "letfdemo-vpc"
    Purpose = "letfdemo"
  }
}

# Internet gateway gives subnet access to the internet
resource "aws_internet_gateway" "demovpc-ig" {
  vpc_id = "${aws_vpc.demovpc.id}"
  tags {
    Name = "letfdemo-ig"
    Purpose = "letfdemo"
  }
}

# Ensure VPC can access internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.demovpc.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.demovpc-ig.id}"

}

# data "aws_route53_zone" "main" {
#   name         = "${var.dns_domain_name}"
#   private_zone = false
# }
#
# resource "aws_route53_record" "letsencrypt-terraform" {
#    zone_id = "${data.aws_route53_zone.main.zone_id}"
#    name    = "${var.dns_domain_subdomain}.${data.aws_route53_zone.main.name}"
#    type    = "CNAME"
#    ttl     = "60"
#    records = ["${var.dns_cname_value}"]
# }

# module "store-server-certs" {
#   source = "../store-server-certs"
#   demo_env_cert_body              = "${module.acme-cert.certificate_pem}"
#   demo_env_cert_chain             = "${module.acme-cert.certificate_issuer_pem}"
#   demo_env_cert_privkey           = "${module.acme-cert.certificate_private_key_pem}"
# }
#
# module "aws-demo-env" {
#     source = "../../modules/aws-demo-environment"
#     demo_env_nginx_count            = "2"
#     demo_env_cert_body              = "${module.acme-cert.certificate_pem}"
#     demo_env_cert_chain             = "${module.acme-cert.certificate_issuer_pem}"
#     demo_env_cert_privkey           = "${module.acme-cert.certificate_private_key_pem}"
# }
