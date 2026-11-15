terraform {
  required_version = ">= 1.10"

  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.30"
    }
  }

  backend "s3" {
    bucket = "homelab-terraform-state"
    key    = "tailscale/terraform.tfstate"

    # Cloudflare R2 endpoint — replace <ACCOUNT_ID> with your Cloudflare account ID
    endpoints = {
      s3 = "https://5f5532f14ac2515183403022a0148383.r2.cloudflarestorage.com"
    }

    region                      = "auto"
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
    use_lockfile                = true
  }
}

provider "tailscale" {
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
  tailnet             = var.tailscale_tailnet

  # These must match the scopes granted to the OAuth client in the admin console,
  # or the token exchange fails: policy_file for tailscale_acl, dns for the DNS
  # resources, devices:core for reading tailnet devices.
  scopes = ["devices:core", "dns", "policy_file"]
}
