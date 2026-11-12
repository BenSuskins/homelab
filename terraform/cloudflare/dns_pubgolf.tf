data "cloudflare_zone" "pubgolf" {
  filter = {
    name = "pubgolf.me"
  }
}

# Root A record. Terraform owns the record's existence and metadata
# (type, proxied, ttl); the cloudflare-ddns container owns the IP value.
# The `content` below is a placeholder — change it to your current public
# IP before the first apply if you want to avoid a brief outage window
# while the ddns container catches up.
resource "cloudflare_dns_record" "pubgolf_root" {
  zone_id = data.cloudflare_zone.pubgolf.zone_id
  name    = "pubgolf.me"
  type    = "A"
  content = "192.0.2.1" # placeholder — updated out-of-band by cloudflare-ddns
  proxied = true
  ttl     = 1

  lifecycle {
    ignore_changes = [content]
  }
}

# Proxied CNAMEs pointing at the apex. Add a subdomain by extending the set.
resource "cloudflare_dns_record" "pubgolf_apex_cnames" {
  for_each = toset(jsondecode(file("${path.module}/public-web.json"))["pubgolf.me"].cnames)

  zone_id = data.cloudflare_zone.pubgolf.zone_id
  name    = each.value
  type    = "CNAME"
  content = "pubgolf.me"
  proxied = true
  ttl     = 1
}

moved {
  from = cloudflare_dns_record.pubgolf_www
  to   = cloudflare_dns_record.pubgolf_apex_cnames["www"]
}

moved {
  from = cloudflare_dns_record.pubgolf_api
  to   = cloudflare_dns_record.pubgolf_apex_cnames["api"]
}

resource "cloudflare_dns_record" "pubgolf_google_verification" {
  zone_id = data.cloudflare_zone.pubgolf.zone_id
  name    = "pubgolf.me"
  type    = "TXT"
  content = "\"google-site-verification=kgHV8yKJS6iaORrmVm2wiE_KXhPPECZZ85KYBh_UQ-8\""
  proxied = false
  ttl     = 3600
}

# Add DNS records for the pubgolf.me zone below.
