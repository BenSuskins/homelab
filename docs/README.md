# homelab

> Ansible-driven infrastructure-as-code for a multi-host homelab.


## Diagram

![Diagram](diagram.png?raw=true "Diagram")


## Overview

Declarative homelab management: containers are defined once per host group
and the playbooks automatically configure Traefik routes, Gatus health
checks, Prometheus scraping, Homepage dashboard entries, and Cloudflare DNS
records. Secrets live in Ansible Vault; Docker image versions are tracked by
Renovate.

## Features

- **Unified service definition** — one YAML block per container drives Traefik, Gatus, Prometheus, Homepage, and DNS
- **Per-group hosts** — `mediaserver`, `docker`, `development`, `monitor`
- **Vault-encrypted secrets** committed alongside the playbooks
- **Renovate-tracked image versions** (pinned, never `:latest`)
- **Generated config templates** for Traefik, Gatus, Prometheus, and Homepage

## Tech Stack

- Ansible 2.12+
- `community.docker.docker_container` for container lifecycle
- Ansible Vault for secrets
- Renovate for image updates
- Terraform (in `terraform/cloudflare/`) for Cloudflare DNS, (in `terraform/proxmox/`) for Proxmox VMs, and (in `terraform/tailscale/`) for tailnet policy and DNS
- Tailscale for remote access (subnet router on the `docker` host)

## Project Structure

```
.
├── inventory                # Host inventory (4 groups)
├── group_vars/              # Global + per-group variables (incl. `containers` lists)
├── plays/                   # Ansible playbooks (setup, deploy-containers, update, clean)
├── tasks/
│   ├── core/                # base.yml, docker.yml
│   ├── docker/              # one file per container (plex.yml, grafana.yml, ...)
│   └── other/               # firewall.yml, etc.
├── config/                  # Traefik, Gatus, Prometheus, Homepage templates
├── terraform/
│   ├── cloudflare/          # Cloudflare DNS, WAF, zone settings
│   ├── proxmox/             # Proxmox VM definitions (bpg/proxmox)
│   └── tailscale/           # Tailnet policy + split DNS (tailscale/tailscale)
└── vault.yml                # Encrypted secrets
```

## Getting Started

### Prerequisites

- Ansible 2.12 or newer (control node)
- SSH key access to every target host (`ssh-copy-id`)
- Ansible Vault password (interactive or `~/.ansible_vault_pass` for CI)

### Setup

```bash
git clone git@github.com:bensuskins/homelab.git
cd homelab

# Update inventory and group_vars/ to match your hosts and domain
vim inventory group_vars/all.yml

# Provision base packages and Docker
ansible-playbook plays/setup.yml --ask-vault-pass

# Deploy all containers + generate Traefik/Gatus/Prometheus/Homepage configs
ansible-playbook plays/deploy-containers.yml --ask-vault-pass
```

Verify: visit the Homepage dashboard hostname configured in `group_vars/all.yml` — every container with `homepage: true` should appear.

## Commands

All playbooks require the vault password (`--ask-vault-pass`). Hosts are Terraform-provisioned with passwordless sudo via cloud-init, so `-K` is not needed.

| Command | Purpose |
|---------|---------|
| `ansible-playbook plays/setup.yml --ask-vault-pass` | One-time host initialisation (base packages, Docker) |
| `ansible-playbook plays/deploy-containers.yml --ask-vault-pass` | Deploy/refresh all containers |
| `ansible-playbook plays/update.yml --ask-vault-pass` | Full update cycle (apt + containers + Traefik/Gatus/Homepage configs); runs on push to `main` |
| `ansible-playbook plays/clean.yml --ask-vault-pass` | apt cache, journal logs, Docker prune |
| `ansible-vault edit vault.yml` | Edit encrypted secrets |

CI reads the vault password from `~/.ansible_vault_pass`.

## Infrastructure (Terraform)

Three independent Terraform roots manage cloud/hypervisor infrastructure, each with its
own remote state in Cloudflare R2:

| Root | Manages |
|------|---------|
| `terraform/cloudflare/` | Cloudflare DNS, WAF, zone settings |
| `terraform/proxmox/` | Proxmox VMs (`bpg/proxmox`) |
| `terraform/tailscale/` | Tailnet policy file and split DNS (`tailscale/tailscale`) |

A single `terraform.yml` workflow runs a **matrix** over all three roots (plan →
manually-approved apply against the `production` environment). It runs on the
**self-hosted** runner because the Proxmox API (`192.168.0.253:8006`) is only reachable
on the LAN.

**Adding a new VM:** copy the commented module block in `terraform/proxmox/vms.tf`,
uncomment it, and set a unique `vm_id`, `ip_address`, and `clone_template_id` (the VM ID
of a prepared cloud-init template). The `./modules/vm` module clones the template and
applies a static IP via cloud-init. New VMs are added to the Ansible `inventory` by hand.

**Prerequisites** (one-time, outside this repo):

- A Proxmox API token (`terraform@pve!<tokenid>=<secret>`) for a user/role with VM
  lifecycle privileges (`VM.Allocate`, `VM.Clone`, `VM.Config.*`, `VM.PowerMgmt`,
  `Datastore.AllocateSpace`, `Datastore.Audit`).
- The cloud-init template described below.
- GitHub secrets `PROXMOX_API_TOKEN` and `PROXMOX_ENDPOINT` (R2 secrets already exist).

### Cloud-init template

`terraform/proxmox/modules/vm` clones every VM from a single golden template
(`clone_template_id`, VM ID **9000** on `local-zfs`):

| Property | Value |
|----------|-------|
| Base image | **Debian 13 "trixie"** generic cloud image (`debian-13-genericcloud-amd64.qcow2`, tracks the latest point release, e.g. 13.5) |
| Guest agent | **`qemu-guest-agent`** baked into the image with `virt-customize` |
| Disk | ~3 GiB native; clones resize up (default 64 GiB) and cloud-init `growpart` expands the root filesystem on first boot |
| Cloud-init | user, SSH key and IP are injected **per clone** by Terraform — the template's cloud-init is left blank so it stays reusable |

The guest agent is baked in (not installed later by Ansible) so the bpg provider
can read each clone's IP at create time — important for DHCP VMs, where the
address isn't known in advance.

Build it once on the Proxmox node:

```bash
cd /var/lib/vz/template
wget https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
virt-customize -a debian-13-genericcloud-amd64.qcow2 --install qemu-guest-agent   # needs libguestfs-tools
qm create 9000 --name debian-13-cloudinit --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 9000 debian-13-genericcloud-amd64.qcow2 local-zfs
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-zfs:vm-9000-disk-0
qm set 9000 --ide2 local-zfs:cloudinit
qm set 9000 --boot c --bootdisk scsi0 --serial0 socket --vga serial0 --agent enabled=1
qm template 9000
```

## Remote Access (Tailscale)

A Tailscale subnet router runs on the `docker` host (`tasks/docker/tailscale.yml`)
advertising `192.168.0.0/24`, so every service is reachable off-LAN with **no inbound
port forwards**. Tailnet split DNS points `suskins.co.uk` at AdGuard Home on the same
host, whose `*.suskins.co.uk` rewrite resolves to Traefik — remote clients therefore
get exactly the same names, routing and TLS as LAN clients.

The tailnet side (policy file, tag owners, route auto-approval, split DNS) is managed
by `terraform/tailscale/`.

**Prerequisites** (one-time, outside this repo):

- A Tailscale **auth key**: reusable, pre-approved, **non-ephemeral** (ephemeral nodes
  are deleted when offline, which would withdraw the route on every reboot), tagged
  `tag:subnet-router`. Store it in the vault as `TAILSCALE_AUTHKEY`.
- A Tailscale **OAuth client** with the `devices:core`, `dns` and `policy_file` scopes,
  for Terraform.
- GitHub secrets `TAILSCALE_OAUTH_CLIENT_ID`, `TAILSCALE_OAUTH_CLIENT_SECRET` and
  `TAILSCALE_TAG_OWNER`.
- `tag:subnet-router` must exist in the tailnet policy before an auth key can carry it,
  so apply `terraform/tailscale/` before minting the key.

Linux clients need `tailscale up --accept-routes`; iOS, Android and macOS accept
advertised routes by default. There is no `tailscale` binary on the host itself — use
`docker exec tailscale tailscale status`.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the system diagram, the unified
service-entry schema, and the full list of deployed services.

## Acknowledgments

- [r/homelab](https://reddit.com/r/homelab) and [r/selfhosted](https://reddit.com/r/selfhosted) communities
- [rishavnandi/ansible_homelab](https://github.com/rishavnandi/ansible_homelab)
- [mazay/truenas-grafana](https://github.com/mazay/truenas-grafana)

## Security

See [SECURITY.md](SECURITY.md) for vulnerability reporting.

## License

[MIT](../LICENSE)
