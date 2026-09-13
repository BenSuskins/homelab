# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ansible configuration for managing a homelab infrastructure with multiple servers running Docker containers. The setup uses Ansible Vault for secrets management and Renovate for automated Docker image updates.

## Common Commands

All playbooks require the vault password (`--ask-vault-pass`). Hosts are Terraform-provisioned with passwordless sudo via cloud-init, so `-K` is not needed:

```bash
# Initial host setup (installs dependencies, docker, reboots)
ansible-playbook plays/setup.yml --ask-vault-pass

# Deploy containers to all hosts
ansible-playbook plays/deploy-containers.yml --ask-vault-pass

# Update packages and containers (runs automatically on push to main)
ansible-playbook plays/update.yml --ask-vault-pass

# Cleanup docker and system files
ansible-playbook plays/clean.yml --ask-vault-pass

# Edit vault secrets
ansible-vault edit vault.yml
```

For CI/CD, vault password is read from `~/.ansible_vault_pass` file.

## Architecture

### Inventory Structure
- `inventory` - Defines 4 host groups: `mediaserver`, `docker`, `development`, `monitor`
- `group_vars/all.yml` - Global variables (timezone, packages, static services)
- `group_vars/<group>.yml` - Per-host variables including `base_dir` and `containers` list

### Playbooks (`plays/`)
- `setup.yml` - One-time host initialization (base packages, Docker install)
- `deploy-containers.yml` - Deploys containers defined in each host's `containers` variable
- `update.yml` - Full update cycle (apt, containers, special services like traefik/gatus/homepage)
- `clean.yml` - System cleanup (apt cache, journal logs, docker prune)

### Task Organization
- `tasks/core/` - Base setup tasks (base.yml, docker.yml)
- `tasks/docker/` - One file per container (e.g., plex.yml, grafana.yml)
- `tasks/other/` - Misc tasks (firewall.yml)

### Container Task Pattern

Each container task file in `tasks/docker/` follows a standard pattern:
1. Create directory with permissions
2. Pre-pull the image using `community.docker.docker_image` (`source: pull`, `force_source: true`), so the download happens before the old container is stopped and the stop→start window stays minimal
3. Create container using `community.docker.docker_container` with `pull: false`
4. Define service entry with metadata (name, ip, port, scheme, etc.)
5. Append to `docker_services` list for Homepage integration

The pre-pull task holds the image reference in a task-level `vars: image:` key and the container task repeats the same literal in its `image:` parameter — Renovate matches `image:` lines, so both are updated together. Keep the two in sync when editing manually.

A container task file may also carry host-level prerequisites for that container, so they only apply where the container is registered: `adguard.yml` disables the systemd-resolved stub listener to free port 53, and `tailscale.yml` loads the `tun` module and enables `net.ipv4.ip_forward` for subnet routing.

Example structure:
```yaml
- name: Create directory
- name: Pre-pull image (docker_image with vars: image: repo/name:tag)
- name: Create container (docker_container with image: repo/name:tag, pull: false)
- name: Define service entry (set_fact with name, ip, port, etc.)
- name: Append to docker_services
```

### Service Entry Variables

Each service entry is a unified definition that controls Homepage, Traefik, Gatus, and Prometheus. Variables are defined in the `set_fact` task for each container.

#### Required Fields

| Variable | Type | Description |
|----------|------|-------------|
| `name` | string | Service identifier, used for container name |
| `ip` | string | Host IP address, typically `{{ inventory_hostname }}` |
| `friendly_name` | string | Group name for Homepage display, typically `{{ friendly_name }}` |

#### Optional Fields

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `description` | string | `name` capitalized | Human-readable description shown on Homepage |
| `icon` | string | `name` lowercase | Homepage dashboard icon (from [Dashboard Icons](https://github.com/walkxcode/dashboard-icons)) |
| `host` | string | none | Full hostname for Traefik routing (e.g., `myapp.suskins.co.uk`) |
| `port` | integer | none | Primary service port |
| `scheme` | string | none | Protocol: `http` or `https` |
| `secured` | boolean | `false` | Requires Authelia authentication via Traefik middleware |
| `homepage` | boolean | `false` | Show on Homepage dashboard |
| `proxied` | boolean | `false` | Include in Traefik routing |
| `path_prefix` | string | none | Restrict Traefik routing to specific path (e.g., `/api/v1`) |
| `proxy_target` | string | `ip` | Override the address Traefik dials for this backend. Only needed when the proxy must reach the container over a shared docker network rather than the host IP — `ip` stays the host address so Gatus/Prometheus keep working from other hosts. |
| `middleware` | string | none | Additional Traefik middleware (e.g., `unifi-headers`) |

#### Gatus Health Monitoring

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `healthcheck` | boolean | `false` | Enable Gatus health monitoring for this service |
| `healthcheck_path` | string | none | Custom health endpoint path (e.g., `/health`, `/api/status`) |

#### Prometheus Metrics

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `metrics` | boolean | `false` | Enable Prometheus scraping for this service |
| `metrics_port` | integer | `port` | Port exposing metrics (if different from service port) |
| `metrics_path` | string | none | Metrics endpoint path (Prometheus assumes `/metrics` if not specified) |

#### Example Service Entry

```yaml
- name: MYAPP - Define service entry
  ansible.builtin.set_fact:
    myapp_entry:
      name: myapp
      description: My application
      icon: myapp
      host: "myapp.{{ domain }}"
      ip: "{{ inventory_hostname }}"
      friendly_name: "{{ friendly_name }}"
      port: 8080
      scheme: http
      secured: true
      healthcheck: true                  # Optional: enable Gatus monitoring
      healthcheck_path: /health          # Optional: custom health endpoint
      homepage: true                     # Optional: show on Homepage
      proxied: true                      # Optional: include in Traefik routing
      path_prefix: /api/v1               # Optional: restrict to specific path
      metrics: true              # Optional: Prometheus scraping
      metrics_port: 9090                 # Optional: if metrics on different port
      metrics_path: /actuator/prometheus # Optional: custom metrics path

- name: MYAPP - Append to docker_services
  ansible.builtin.set_fact:
    docker_services: "{{ docker_services + [myapp_entry] }}"
```

### Service Discovery

The `docker_services` list is aggregated across all hosts via `tasks/core/aggregate_services.yml` and used to:
- Auto-generate Homepage entries via `config/homepage/services.yaml.j2`
- Configure Traefik routing via `config/traefik/dynamic/http.yml.j2`
- Set up Gatus monitoring via `config/gatus/config.yaml.j2`
- Generate Prometheus scrape configs via `config/prometheus/config.yml.j2`
- Cloudflare DNS records are managed via Terraform in `terraform/cloudflare/`

Proxmox VMs are managed via a separate Terraform root in `terraform/proxmox/` (bpg/proxmox provider). Each VM lives in its own `<name>.tf` file (e.g. `bumblebee.tf`) holding its `module` block and IP `output`; add a new VM by copying the commented template in `terraform/proxmox/vms.tf` into a new per-host file.

Tailnet configuration lives in a third root, `terraform/tailscale/` (tailscale/tailscale provider): the policy file (`tag:subnet-router` tag owners plus `autoApprovers` so the advertised LAN route needs no manual approval) and split DNS sending `suskins.co.uk` at AdGuard Home. Note `tailscale_acl` owns the *whole* policy file, so import it before the first apply if the console copy has been hand-edited.

Each Terraform root has its own R2 state key. A single `terraform.yml` workflow runs a matrix (plan → approved apply) over all three roots on the `self-hosted` runner, since the Proxmox API is LAN-only.

### Remote Access

A Tailscale subnet router runs on the `docker` host (`tasks/docker/tailscale.yml`) advertising `192.168.0.0/24`, so every homelab service is reachable remotely with no inbound port forwards. Tailnet split DNS points `suskins.co.uk` at AdGuard Home on the same host, whose `*.suskins.co.uk` rewrite resolves to Traefik — so remote clients get the identical name resolution and TLS path as LAN clients. There is no `tailscale` binary on the host; use `docker exec tailscale tailscale status`.

### Grafana Dashboards

Dashboards live in `config/grafana/dashboards/<Folder>/<uid>.json` and are provisioned from the directory structure (`foldersFromFilesStructure: true`), so the folder is the Grafana folder and the filename must match the dashboard's `uid`.

**Read `docs/grafana-dashboard-style.md` before adding or editing a dashboard.** It is the design system every dashboard follows — top-bar nav block, `Status → Topic… → Detail` section grammar, KPI tile geometry, the two legend modes, threshold ladders, and the locked dashboard defaults. There is no linter, so that document is the only thing preventing drift; it ends with a checklist.

Two dashboards (`traefik.json`, `truenas.json`) were previously community imports and are now hand-maintained — do not re-import them from grafana.com. See `docs/adr/0002-hand-built-traefik-and-truenas-dashboards.md`.

Dashboards are copied to the host with `copy`, which never deletes — so `grafana.yml` reconciles the host against the repo each run and removes dashboards that no longer exist here. Renaming a dashboard therefore means changing title, `uid` **and** filename together.

Alerting is provisioned from `config/grafana/provisioning/alerting/` (rules, mute times), except **contact points and notification policies**, which are templated from `config/grafana/templates/*.j2` because they carry the Discord webhook. Set `GRAFANA_ALERT_DISCORD_URL` in vault to route alerts to Discord; without it both templates fall back to the email contact point. Grafana's notification templates use `{{ }}` too, so anything Grafana must evaluate is wrapped in `{% raw %}`.

Host identification is governed by `docs/adr/0001-host-label-canonical-for-dashboards.md`: filter and display by the `host` label, never `instance`, and never use `up` to test whether a host is alive.

### Docker Image Updates

Renovate monitors `tasks/docker/*.yml` for Docker image versions and creates PRs for updates. Images are pinned to specific versions (not `latest`).

### Apps (`apps/`)

Three Swift packages:

- **`apps/homelab-core/`** — `HomelabCore`, shared by both apps: domain types, `GitHubClient`, `StatusSnapshot`, `AppState`, the polling schedule, and the Prometheus client. Every testable decision lives here. Nothing in it imports AppKit, `ServiceManagement` or `Process`.
- **`apps/homelab-menubar/`** — the macOS menu bar app: menu views, settings window, login item, and `GhCommandTransport`.
- **`apps/homelab-ios/`** — the iOS app and its widget. An Xcode project generated by XcodeGen from `project.yml`; the `.xcodeproj` is gitignored.

From `apps/homelab-menubar/`: `make test` (both packages), `make bundle`, `make install`, `make ios-generate`, `make ios-build`.

All GitHub access goes through the `GitHubTransport` protocol, which is the only seam tests fake. macOS shells out to `gh` and holds no token; iOS cannot spawn a subprocess, so it holds an OAuth token in the Keychain and gates every write behind biometrics — `docs/adr/0004-the-ios-app-holds-a-token.md`. iOS wires up no notifier at all, because a suspended app never sees the failure — `docs/adr/0005-ios-ambient-status-is-a-widget.md`.

`openPullRequests()` uses GraphQL, not REST, and must stay that way: REST's `/pulls` list endpoint does not return `mergeable` at all, so a "simplification" to REST silently breaks `canMerge`.

**`update.yml` and `build-mcp-arr.yml` carry `paths-ignore: ['apps/**']`.** Both trigger on every push to `main`; without those blocks a commit touching only Swift code runs Ansible against all six hosts. Do not remove them. `apps.yml` is the other half of that pair — it runs on `paths: ['apps/**']` and is the only workflow that builds or tests the Swift. It needs a GitHub-hosted macOS runner; the `self-hosted` one is Linux. See `docs/adr/0003-menu-bar-app-lives-in-this-repo.md`.

`docs/ios-app-scope.md` is the plan the apps were built to, including the roadmap past v1 (service directory, log viewer, metrics, SSH).

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (via the `gh` CLI). See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context layout — `CONTEXT.md` + `docs/adr/` at the repo root (created lazily as terms/decisions get resolved). See `docs/agents/domain.md`.
