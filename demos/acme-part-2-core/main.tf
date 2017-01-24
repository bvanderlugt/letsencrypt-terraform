# ---------------------------------------------------------
# Load the outputs from part 1 of the separately managed 
# process (terraform acme registration in this case)
# ---------------------------------------------------------
data "terraform_remote_state" "letsencrypt_registration" {
    backend = "local"
    config {
        path = "${path.root}/../acme-part-1-registration/terraform.tfstate"
    }
}

# ---------------------------------------------------------
# Perform part 2 of the demo setup
# ---------------------------------------------------------
module "dns" {
    source = "../../modules/dns/indirect"
    dns_domain_name               = "${var.demo_domain_name}" 
    dns_domain_subdomain          = "${var.demo_domain_subdomain}" 
    dns_cname_value               = "${module.aws-demo-env.demo_env_elb_dnsname}"
}

module "acme-cert" {
    source = "../../modules/acme-cert-request"
    acme_server_url               = "${data.terraform_remote_state.letsencrypt_registration.server_url}" 
    acme_account_registration_url = "${data.terraform_remote_state.letsencrypt_registration.registration_url}"
    acme_account_key_pem          = "${data.terraform_remote_state.letsencrypt_registration.registration_private_key_pem}"  
    acme_certificate_common_name  = "${module.dns.fqdn_domain_name}"
    # To make use of a single direct DNS record, comment out the line 
    # above, uncomment the one below, and ensure the dns module source
    # is loaded from modules/dns/direct. This current approach has been
    # done to remove a cyclic dependency.
    # acme_certificate_common_name  = "${var.demo_domain_name}.${var.demo_domain_subdomain}"

    acme_challenge_aws_access_key_id     = "${var.demo_acme_challenge_aws_access_key_id}"
    acme_challenge_aws_secret_access_key = "${var.demo_acme_challenge_aws_secret_access_key}"
    acme_challenge_aws_region            = "${var.demo_acme_challenge_aws_region}" 
}


module "aws-demo-env" {
    source = "../../modules/aws-demo-environment"
    demo_env_nginx_count                = "2"
    demo_env_cert_body                  = "${module.acme-cert.certificate_pem}"      
    demo_env_cert_chain                 = "${module.acme-cert.certificate_issuer_pem}" 
    demo_env_cert_privkey               = "${module.acme-cert.certificate_private_key_pem}" 
}