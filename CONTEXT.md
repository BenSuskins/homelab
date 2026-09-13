# Homelab Ansible Plays

Ansible-based configuration management for a self-hosted homelab: Docker containers spread across several hosts, a unified service-discovery mechanism that drives Homepage/Traefik/Gatus/Prometheus, and three independent Terraform roots for Proxmox, Cloudflare, and Tailscale.

## Language

### Hosts & Inventory

**Host Group**:
An Ansible inventory group (`mediaserver`, `docker`, `development`, `monitor`, `bumblebee`, `ai`) that maps to exactly one physical or virtual machine, with its own `group_vars/<group>.yml` defining that host's `base_dir` and `containers`.
_Avoid_: Server, node

**Friendly Name**:
The human-readable label for a host (e.g. "Media", "Docker", "Monitoring") used to group that host's services together on the Homepage dashboard. Set as `friendly_name` in the `inventory` file — distinct from the host's IP or Ansible user.
_Avoid_: Display name, label

**Base Dir**:
The root directory on a host (e.g. `/home/docker/server-docker`) under which every container on that host stores its config and data via bind mounts. Defined once per host in `group_vars/<group>.yml`.
_Avoid_: Data dir, install dir

**Domain**:
The DNS zone (`suskins.co.uk`) that all service hostnames are built under, e.g. `myapp.{{ domain }}`. Defined once in `group_vars/all.yml`.

### Service Definition

**Service Entry**:
The single `set_fact` object a Container Task defines to describe how that container is exposed. One Service Entry drives four systems at once — Homepage listing, Traefik routing, Gatus health monitoring, Prometheus scraping — with fields like `homepage`, `proxied`, `healthcheck`, and `metrics` opting into each independently.
_Avoid_: Service definition, service config

**Container Task**:
The standard task file in `tasks/docker/<name>.yml` that creates one container. Always follows the same shape: create directory, pre-pull the image, create the container with `pull: false`, define the container's Service Entry, append it to `docker_services`.
_Avoid_: Container role, container playbook

**`docker_services`**:
The list of every Service Entry across all hosts, aggregated by `tasks/core/aggregate_services.yml` and consumed by the Jinja templates that generate Homepage, Traefik, Gatus, and Prometheus config.
_Avoid_: Service list, service registry

**Secured**:
A Service Entry flag meaning the service's Traefik route requires Authelia authentication. Distinct from `proxied`, which only controls whether the service is routed through Traefik at all.

### Monitoring & Metrics

**Host Label**:
The Prometheus label `host`, set to a host's Friendly Name on every metric series — either via a Service Entry's `host: "{{ svc.friendly_name }}"` static scrape label, or via Alloy's `set_instance` relabel rule for pushed metrics. This is the only label dashboards should filter or group by when the axis is "which host". Distinct from the `instance` label, which holds the host's raw IP and exists for Prometheus's own target bookkeeping, not for display.
_Avoid_: `instance` label (for host identification or display), IP-based filtering

**PVE Node**:
A Proxmox hypervisor, identified by the `node` label on `pve_*` metrics. Not a Host — it is the machine the Hosts run *on*, and it has no Host Label. This is why the Proxmox dashboard filters by `$node` rather than `$host`.
_Avoid_: calling a PVE Node a host or a server

**Guest**:
A VM or container managed by Proxmox, identified by the `id` label on `pve_*` metrics in the form `qemu/101`. The six Guests happen to be the same machines as the six Hosts, but they carry no Host Label — pve-exporter knows them only by numeric id. Filtering Guests uses `$guest`, and Guest panels legend by id, not by Friendly Name.
_Avoid_: VM (ambiguous — a Guest may be a container), treating a Guest id as a Host Label

**Remote-Written Metric**:
A metric series that reaches Prometheus via Alloy's `remote_write` push (host metrics like `node_*`, container metrics like `container_*`) rather than by being scraped directly. Remote-written series never produce a corresponding `up` series, so `up` cannot be used to test liveness, enumerate hosts, or build template variables for anything in this category — query the metric itself instead. Contrast with a **Scraped Metric** (an app's own `/metrics` endpoint, opted into via a Service Entry's `metrics: true`), which does get an `up` series.
_Avoid_: using `up` as a stand-in for "is this host/container reporting"

### Dashboard Structure

**Status Strip**:
The row of equal-width stat tiles at the top of a dashboard, answering "is this thing OK right now" without requiring interpretation. Exactly one per dashboard, always the first section. Distinct from a topic-scoped strip, which sits inside a Topic Section and is narrower in scope.
_Avoid_: header row, summary row

**Topic Section**:
A row grouping the charts for one subject — `Resource Usage`, `Storage`, `Latency`, `Traffic`. Named for what it shows, never for the dashboard it lives on. May open with its own KPI strip before its charts.
_Avoid_: category, group

**Detail Section**:
The last expanded row on a dashboard, holding tables and per-entity fan-outs (one series per host, container or disk) rather than time series.

**Deep Dive**:
The single optional collapsed row permitted at the very end of a dashboard, holding internals that are genuinely rare to need — ZFS ARC breakdown, NFS RPC, per-disk latency. Capped at one per dashboard so that collapsing does not become the default habit, which is what made the imported TrueNAS and Traefik dashboards unreadable.
_Avoid_: Advanced, Misc, Other

### Infrastructure as Code

**Terraform Root**:
One of three independent Terraform state trees (`terraform/proxmox`, `terraform/cloudflare`, `terraform/tailscale`), each with its own R2 state key and its own plan/apply stage in the `terraform.yml` workflow matrix. They are not layered or dependent on one another.
_Avoid_: Terraform module, stack

**Subnet Router**:
The Tailscale node running on the `docker` host that advertises the home LAN CIDR (`192.168.0.0/24`) to the tailnet, so any tailnet device can reach homelab services without inbound port forwarding.
_Avoid_: VPN gateway, relay

### Apps

**Dispatchable Workflow**:
One of the three workflows the menu bar app is allowed to start on demand — `update.yml`, `terraform.yml`, `clean.yml`. The repository holds other workflows (`build-mcp-arr.yml`); a workflow is Dispatchable only if starting it by hand is a thing you'd deliberately do. Distinct from merely carrying a `workflow_dispatch` trigger.
_Avoid_: job, action, pipeline

**Run Row**:
One line of the menu describing the most recent run of a Dispatchable Workflow on `main`, together with whether it can currently be triggered or cancelled. A Run Row is always present for all three workflows even when one has never run, so rows never appear or disappear between refreshes.
_Avoid_: workflow row, status row

**Glyph State**:
What the menu bar icon shows while the menu is closed, collapsed from every Run Row to the worst thing any of them is doing: `failed` beats `running` beats `ok`. It answers one question — "do I need to open this?" — and deliberately does not distinguish which workflow is responsible. A run Awaiting Approval does not raise it.
_Avoid_: icon state, badge

**Awaiting Approval**:
A run that has reached an environment gate with required reviewers and stopped. Terraform does this on every run, between plan and apply. It is not running (nothing is executing) and not finished (no conclusion), but it still owns the workflow, so triggering another would race it.
_Avoid_: pending, blocked, waiting (ambiguous with queued)

**Status Snapshot**:
The immutable value describing everything a surface renders at one moment — the macOS menu, the iOS Runs tab, the widget. Produced from fetched data, consumed by the view, and cached to disk verbatim so each paints instantly at launch. Every question the view can ask is answered on the Snapshot, so the view holds no logic. Called `MenuSnapshot` until there was more than a menu.
_Avoid_: view model, menu state, Menu Snapshot

**Transport**:
The single impure step between `GitHubClient` and GitHub, behind the `GitHubTransport` protocol. There are exactly two: `GhCommandTransport` renders a request into `gh` argv on macOS, and `URLSessionTransport` sends it to `api.github.com` with a bearer token on iOS. The client builds a `GitHubRequest` — a method, a path and fields, or a GraphQL query — and does not know which transport will carry it.
_Avoid_: client, backend, API layer

**Token Store**:
Where the iOS app keeps its GitHub credential, behind the `TokenStoring` protocol so the Keychain is faked in tests like every other boundary. The macOS app has none — that is the whole distinction ADR-0004 records.
_Avoid_: credential manager, keychain wrapper

**Health Grid**:
The iOS health screen's per-service up/down display, built from `gatus_results_endpoint_success` read straight from Prometheus over the tailnet and grouped by Host Label. Distinct from Gatus's own web UI, which it deliberately does not proxy or embed.
_Avoid_: status page, uptime screen

**Write**:
Any of the three operations that change something on GitHub — dispatch, cancel, squash merge. Named as a category because they share one rule: on iOS every Write is behind a biometric prompt and no read ever is.
_Avoid_: action, mutation, command
