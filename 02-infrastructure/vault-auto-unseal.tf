data "aws_iam_policy_document" "vault_auto_unseal_kms" {
  statement {
    sid    = "AllowVaultKMSAutoUnseal"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = [aws_kms_key.vault_auto_unseal.arn]
  }
}

resource "aws_kms_key" "vault_auto_unseal" {
  description             = "KMS key for HashiCorp Vault auto-unseal"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "vault_auto_unseal" {
  name          = var.vault_auto_unseal_kms_alias
  target_key_id = aws_kms_key.vault_auto_unseal.key_id
}

resource "aws_iam_user" "vault_auto_unseal" {
  name = var.vault_auto_unseal_iam_user_name
  path = "/system/"
}

resource "aws_iam_user_policy" "vault_auto_unseal" {
  name   = "vault-auto-unseal-kms"
  user   = aws_iam_user.vault_auto_unseal.name
  policy = data.aws_iam_policy_document.vault_auto_unseal_kms.json
}

resource "aws_iam_access_key" "vault_auto_unseal" {
  user = aws_iam_user.vault_auto_unseal.name
}
