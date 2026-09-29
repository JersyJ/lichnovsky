terraform {
  required_version = ">= 1.12.0" # OpenTofu (state encryption + early-evaluated variables)

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.26.0"
    }
  }

  # R2 through its S3 API (not AWS). Keys: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY.
  backend "s3" {
    bucket = "lichnovsky-tofu-state"
    key    = "cloudflare/terraform.tfstate"
    region = "auto"
    endpoints = {
      s3 = "https://b125c4cecdc50a6592a274152b09b350.r2.cloudflarestorage.com"
    }
    use_path_style              = true
    use_lockfile                = true # R2 supports the conditional writes this needs
    skip_credentials_validation = true # these skips stop OpenTofu from calling AWS services
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true # R2 doesn't implement the AWS checksum headers
  }

  # The state holds the tunnel secret, so state and plans are encrypted (TF_VAR_state_passphrase).
  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }
    state {
      method   = method.aes_gcm.main
      enforced = true
    }
    plan {
      method   = method.aes_gcm.main
      enforced = true
    }
  }
}

# Auth: CLOUDFLARE_API_TOKEN.
provider "cloudflare" {}
