# Troubleshooting

## Deployment

**Private routes or Authelia stop working after a Traefik update**

Before the cutover, put a dedicated `TRAEFIK_CLOUDFLARE_DNS_API_TOKEN` in the
Ansible vault used by the deployment workflow. Give it Zone Read and DNS Edit
permissions for `suskins.co.uk`. Verify its permissions and DNS challenge access
before merging. The generated certificate covers the apex and wildcard; it does
not publish private services in DNS. Traefik persists its ACME account and
certificate in `traefik/acme/acme.json`. Back up this file as a secret.

Check the Traefik logs for ACME errors. Check the certificate presented for both
`hub.suskins.co.uk` and `authelia.suskins.co.uk` from a LAN device. Check a
Tailscale client as well. Private routes allow the connection's source address
in `traefik_private_networks`; forwarded headers do not grant access. The current
subnet router uses source NAT, so its LAN address is allowed by that network.
Confirm the actual source address after any network or router change.

Before merging, test the public routes externally and inspect the router's port
forwards. Docker publishes service ports independently of Traefik; the Traefik
allowlist does not protect those ports. Confirm that no private backend port is
reachable from the internet. Test a private hostname from outside, including a
request with a forged forwarding header, and confirm it is rejected.

For rollback, revert the change and use the reviewed deployment workflow. Keep
the previous local wildcard and Authelia certificate files until the new
certificate, public routes, LAN access, and Tailscale access have passed their
checks. Do not delete ACME state during rollback.

**The deployment reports that public DNS and Traefik routes disagree**

Set `public: true` on a proxied service only when it is intended to be public.
Add or remove its DNS name in `terraform/cloudflare/public-web.json` as well.
List edge redirects or other names that do not route through Traefik as
`non_route_hosts`. Review Terraform's plan before applying DNS changes.
