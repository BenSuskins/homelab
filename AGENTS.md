# Agent guide

## Project

This repository manages the homelab with Ansible and Terraform. It also contains shared Swift packages and macOS/iOS apps under `apps/`.

Follow the existing code and configuration style. Keep changes scoped. Preserve unrelated work. Prefer clear names and self-documenting code. Explain why in comments when needed.

## Ansible

All playbooks need the Ansible Vault password. Hosts use passwordless sudo; do not add `-K`.

```sh
ansible-playbook plays/setup.yml --ask-vault-pass
ansible-playbook plays/deploy-containers.yml --ask-vault-pass
ansible-playbook plays/update.yml --ask-vault-pass
ansible-playbook plays/clean.yml --ask-vault-pass
ansible-vault edit vault.yml
```

The inventory defines `mediaserver`, `docker`, `development`, and `monitor` groups. Shared variables live in `group_vars/all.yml`; host-group variables and container registrations live in `group_vars/`.

Container tasks live in `tasks/docker/`. Follow the existing pattern: create required directories, pre-pull the pinned image with `docker_image` and `force_source: true`, create the container with `pull: false`, define its service entry, then append it to `docker_services`. Keep the image reference in the pre-pull task and container task identical so Renovate updates both. Container-specific host prerequisites belong in that container's task file.

Service entries drive Homepage, Traefik, Gatus, and Prometheus. Check existing entries and the templates under `config/` before changing fields or behavior. Use `proxy_target` only when Traefik must reach a container over a shared Docker network; keep `ip` as the host address for monitoring.

## Terraform

Terraform has separate roots in `terraform/cloudflare/`, `terraform/proxmox/`, and `terraform/tailscale/`. Each root has independent state. Proxmox VMs use one `<host>.tf` file each. The Terraform workflow plans each root and gates applies. Do not apply infrastructure changes outside the repository's reviewed workflow unless the user explicitly asks.

## Grafana

Read `docs/grafana-dashboard-style.md` before editing dashboards. Dashboards live in `config/grafana/dashboards/<Folder>/<uid>.json`; the filename must match the dashboard UID. `traefik.json` and `truenas.json` are hand-maintained. Follow `docs/adr/0001-host-label-canonical-for-dashboards.md`: use the `host` label, not `instance`, and do not use `up` as a host-liveness check.

Alert rules and mute times live in `config/grafana/provisioning/alerting/`. Contact points and notification policies are templated under `config/grafana/templates/` because they include the Discord webhook. Preserve `{% raw %}` around Grafana template expressions.

## Swift apps

- `apps/homelab-core/` contains shared domain logic and clients. Keep it independent of AppKit, `ServiceManagement`, and `Process`.
- `apps/homelab-menubar/` contains the macOS menu bar app.
- `apps/homelab-ios/` contains the iOS app and widgets. `Homelab.xcodeproj` is committed and is the Xcode Cloud source of truth. Add new source files to both the project group and the target's sources build phase.
- `GitHubTransport` is the seam for GitHub access. Keep `openPullRequests()` on GraphQL because the REST list endpoint omits mergeability.
- Build Loki and Prometheus query strings with `QueryEncoding`; `URLComponents.queryItems` leaves `+` unescaped for Go query parsing.
- Keep `paths-ignore: ['apps/**']` in `update.yml` so app-only changes do not deploy infrastructure. `apps.yml` is the Swift workflow and requires a GitHub-hosted macOS runner.

From `apps/homelab-menubar/`, `make test` runs both package test suites. Other supported commands include `make bundle`, `make install`, `make ios-generate`, and `make ios-build`.

## Verification and safety

For Ansible, Terraform, and other infrastructure changes, verify with the relevant syntax, validation, or plan command before applying anything. Do not expose vault values, tokens, or other secrets in output.

For Swift changes, use the package or Xcode command for the affected target. Do not claim that a build or workflow proves installed-device behavior. Do not trigger deployment or production infrastructure changes unless requested.

The `update.yml` workflow runs Ansible against hosts on pushes to `main`, excluding app-only changes. Keep its path filter intact when changing app-only code.
