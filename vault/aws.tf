
# The mount is TF-managed but `aws/config/root` is written once by hand so the engine's IAM key never enters Terraform state.
resource "vault_mount" "aws" {
  path        = "aws"
  type        = "aws"
  description = "STS credentials for the S3 Terraform state backend"
}

resource "vault_aws_secret_backend_role" "tfstate" {
  backend         = vault_mount.aws.path
  name            = "tfstate"
  credential_type = "assumed_role"
  role_arns       = [var.aws_tfstate_role_arn]

  default_sts_ttl = 3600
  max_sts_ttl     = 3600
}

resource "vault_policy" "aws_tfstate" {
  name = "aws-tfstate"

  policy = <<-EOT
    path "aws/creds/${vault_aws_secret_backend_role.tfstate.name}" {
      capabilities = ["read"]
    }
  EOT
}
