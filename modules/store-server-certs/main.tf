resource "aws_iam_server_certificate" "elb_cert" {
  name_prefix       = "letfdemo-cert-"
  certificate_body  = "${var.demo_env_cert_body}"
  certificate_chain = "${var.demo_env_cert_chain}"
  private_key       = "${var.demo_env_cert_privkey}"

  lifecycle {
    create_before_destroy = true
  }
}
