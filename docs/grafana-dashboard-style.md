# Grafana Dashboard Style Guide

Every dashboard in `config/grafana/dashboards/` follows this. It was extracted
from `Overview/homelab-overview.json`, which is the reference implementation —
when this document and that file disagree, fix whichever is wrong and say so
here.

There is no linter. This document is the only thing holding the line, so read
it before adding or editing a dashboard.

## 1. Top bar

Identical block in every dashboard, including Overview itself. A self-link on
Overview is harmless and keeps the block a single copy-paste unit with no
per-file special-casing.

```json
"links": [
  { "type": "link", "title": "Overview", "url": "/d/homelab-overview",
    "keepTime": true, "icon": "dashboard" },
  { "type": "dashboards", "title": "Infrastructure", "tags": ["infrastructure"],
    "asDropdown": true, "keepTime": true },
  { "type": "dashboards", "title": "Apps", "tags": ["apps"],
    "asDropdown": true, "keepTime": true },
  { "type": "dashboards", "title": "Monitoring", "tags": ["monitoring"],
    "asDropdown": true, "keepTime": true }
]
```

The dropdowns are driven by **tags**, not by folder. A dashboard must carry the
tag matching its folder or it will not appear in its own dropdown:

| Folder | Tags |
|---|---|
| `Overview/` | `homelab`, `overview` |
| `Infrastructure/` | `homelab`, `infrastructure`, `<topic>` |
| `Apps/` | `homelab`, `apps`, `<topic>` |
| `Monitoring/` | `homelab`, `monitoring`, `<topic>` |

`keepTime: true` everywhere means the selected time range survives navigation.

## 2. Section grammar

```
── Status ──────────────────────────────────
 [ KPI ][ KPI ][ KPI ][ KPI ]
── <Topic> ─────────────────────────────────
 [ 12w chart ][ 12w chart ]
 [ 12w chart ][ 12w chart ]
── <Topic 2> ───────────────────────────────
 [ KPI ][ KPI ][ KPI ][ KPI ]        ← topic-scoped, optional
 [ 12w chart ][ 12w chart ]
── Detail ──────────────────────────────────
 [ 24w table / per-entity fan-out          ]
▸ Deep Dive                                  ← collapsed, optional, last, max one
```

Rules:

- **Every panel lives under a row.** No orphan panels. The one exception is
  Overview's `alertlist`, which sits above the first row deliberately.
- **`Status` comes first** and answers "is this thing OK right now" in tiles you
  can read without thinking.
- **Topic sections** are named for the thing they show (`Resource Usage`,
  `Storage`, `Latency`, `Traffic`) — never for the dashboard
  (`── Tailscale ──` on the Tailscale dashboard says nothing).
- A Topic section **may** open with its own KPI strip scoped to that topic,
  followed by its charts. `Status` is the dashboard-wide strip; a topic strip is
  narrower in scope, not a second Status.
- **`Detail` is optional and last** among expanded sections, and holds tables and
  per-entity fan-outs. A dashboard with nothing to tabulate simply ends on its
  last Topic — do not invent a Detail section to fill the shape.
- **Everything is expanded.** A dashboard may add at most **one** trailing
  collapsed section named `Deep Dive`, for genuinely rare internals (ZFS ARC
  breakdown, NFS RPC, per-disk latency). One named exception, so it cannot
  quietly become the norm. If you want a second, cut something instead.

Landing on a dashboard and scrolling once should show you the whole picture.
That is the property that makes Overview feel coherent, and it is the first
thing collapsed rows destroy.

## 3. Layout geometry

The grid is 24 columns wide.

### KPI tiles (Status strips and topic strips)

- height **4**
- every tile in a strip is the **same width** as its neighbours
- the strip fills **exactly 24 columns** — no gaps, no overflow

Legal strip shapes: `6w × 4`, `8w × 3`, `4w × 6`, `12w × 2`.

```
legal    [ 6w ][ 6w ][ 6w ][ 6w ]
         [  8w  ][  8w  ][  8w  ]
         [4w][4w][4w][4w][4w][4w]

illegal  [ 6w ][ 6w ][ gap ][ 6w ]     ← dead column
         [ 6w ][ 6w ][4w][4w][4w]      ← mixed widths
```

### Charts

- **12w × 8h**, two per row — the default
- **24w × 8h** for a single chart that genuinely needs the width
- **8w × 8h**, three per row, when three charts are one thought (p50/p95/p99)

### Tables and fan-outs

- tables: **24w**, height 6–8
- per-entity stat fan-out (one series per host, `textMode: value_and_name`):
  **24w × 4h**

## 4. Panel tokens

### Stat

```json
"options": {
  "textMode": "value",           // "value_and_name" for multi-series fan-outs
  "colorMode": "background",
  "graphMode": "none",
  "reduceOptions": { "calcs": ["lastNotNull"] }
}
```

`colorMode: background` is not decoration — it is what makes a 24w fan-out
strip scannable at a glance. Do not switch it to `value`.

### Timeseries

```json
"fieldConfig": { "defaults": { "custom": { "fillOpacity": 20, "lineWidth": 2 } } },
"options": { "tooltip": { "mode": "multi" }, "legend": { ... } }
```

Legend has **two** modes, chosen by how many series the panel can produce:

| Series count | Legend |
|---|---|
| **Bounded** (≲10 — per-host, per-node, quantiles) | `displayMode: table`, `placement: bottom`, `calcs: ["mean","max"]` |
| **Unbounded** (per-container, per-guest, per-endpoint, per-disk) | `displayMode: list`, `placement: bottom`, `calcs: []` |

The repo runs 36 containers across 6 hosts. A table legend with `mean`/`max` on
a 36-series panel is taller than the plot, which is why the second mode exists.
It is a deliberate mode, not drift — but do not reach for it on a panel that
can only ever emit six lines.

### Units

Always set one. `percentunit` (0–1) with `min: 0, max: 1` for ratios,
`percent` (0–100) with `max: 100`, `bytes`, `Bps`, `s`, `celsius`, `short`.

## 5. Threshold ladders

Colour must mean the same thing on every dashboard. Pick the ladder that matches
what the number *is*. `base` is always the first step, with `"value": null`.

**Lower is better** — ladder runs green → orange → red:

| Kind | Steps |
|---|---|
| **Utilisation** (`percentunit`) | `green` · `orange` 0.80 · `red` 0.90 |
| **Utilisation** (`percent`) | `green` · `orange` 80 · `red` 90 |
| **Error rate** (`percentunit`) | `green` · `orange` 0.01 · `red` 0.05 |
| **Latency** (`s`) | `green` · `orange` 0.3 · `red` 1.2 |
| **Temperature** (`celsius`) | `green` · `orange` 60 · `red` 75 |
| **Fault count** (things that should be zero) | `green` · `red` 1 |

**Higher is better** — ladder runs red → orange → green:

| Kind | Steps |
|---|---|
| **Liveness** (0/1) | `red` · `green` 1 |
| **Availability** (`percentunit`) | `red` · `orange` 0.99 · `green` 0.999 |
| **Uptime** (`s`) | `red` · `orange` 86400 (1d) · `green` 604800 (7d) |
| **Free space** (`bytes`) | `red` · `orange` 10 GiB · `green` 50 GiB |
| **Certificate life** (`d`) | `red` · `orange` 14 · `green` 30 |

**Neither** — a count with no good or bad value (hosts reporting, containers
running, routes advertised, games in progress):

| Kind | Steps |
|---|---|
| **Informational** | single `green` step |

The latency ladder's 0.3 / 1.2 are the same targets Traefik's SLO panels use, so
a red latency tile and a failing SLO chart agree with each other.

If a number does not fit any of these, use the informational ladder — a tile
that is red for no defined reason trains you to ignore red. Adding a new ladder
is fine; add it to this table at the same time, and use it in more than one
place or it is not a ladder, it is a one-off.

## 6. Locked dashboard defaults

Identical in all 11:

```json
"refresh": "1m",
"graphTooltip": 1,
"schemaVersion": 39,
"editable": true,
"timezone": "",
"fiscalYearStartMonth": 0,
"id": null
```

`graphTooltip: 1` is the shared crosshair — with it, hovering one panel marks the
same instant on every other, which is most of the value of putting related
charts side by side.

Default **time range** is `now-6h`, except where the subject has a natural
window. These are the only exemptions, and adding another needs a reason
written down here:

| Dashboard | Range | Why |
|---|---|---|
| Pubgolf | `now-90d` | product metrics are counted per day |
| Health Checks | `now-24h` | the SLO window is 24h / 30d |
| Logs | `now-1h` | log volume at 6h is unreadable |

## 7. Template variables

The **Host Label** (`host`, holding a host's Friendly Name) is the only label a
dashboard uses to identify a host.

- A host-scoped dashboard leads with a variable literally named **`host`**:
  `multi: true`, `includeAll: true`, `allValue: ".*"`.
- Source it from a **remote-written** metric that actually exists per host, not
  from `up` — host metrics arrive via Alloy's `remote_write` and never produce
  an `up` series.
- Later variables narrow within it, broadest scope first.
- Single-host dashboards (Home Assistant, Tailscale) and non-host ones (Logs,
  Pubgolf) do not get a `host` variable. A dropdown with one entry that can only
  filter things to nothing teaches you to ignore the picker row.

**Gatus**: its `group` label holds the Friendly Name, so the variable is named
`host` and queries write `group=~"$host"`.

**Proxmox** is the deliberate exception. A PVE Node is a hypervisor and a Guest
is a `qemu/NNN` id — neither is a Host Label, so Proxmox keeps `$node` and
`$guest`. A PVE node is a hypervisor; a guest is a `qemu/NNN` ID. Do not "fix"
these into `$host`.

## 8. Naming

- **Dashboard title** is short and unqualified — `Containers`, `Health`,
  `Traefik`. The folder supplies the context, so `Docker Containers` in the
  `Infrastructure` folder is redundant.
- **`uid`** is stable, kebab-case, and matches the filename. It changes only
  when a dashboard is deliberately renamed, and that costs every bookmark and
  saved link to it — `Gatus SLO`/`gatus-slo` became `Health Checks`/`health-checks`
  and `Health`/`monitoring-health` became `Observability`/`observability` on
  exactly those terms. Never change it incidentally.
- **Panel titles** say what the number is, not which metric produced it.

## 9. Checklist

Before committing a dashboard:

- [ ] nav block present and byte-identical to §1
- [ ] tagged with its folder's tag
- [ ] every panel under a row; no vanity row repeating the title
- [ ] `Status` first, `Detail` last, at most one trailing collapsed `Deep Dive`
- [ ] every KPI strip is equal-width and sums to exactly 24
- [ ] no `gridPos` overlaps
- [ ] stats: `background` / `none` / `lastNotNull`
- [ ] timeseries: `fillOpacity: 20`, `lineWidth: 2`, tooltip `multi`
- [ ] legend mode matches the panel's series cardinality
- [ ] every panel has a unit
- [ ] thresholds use a ladder from §5
- [ ] locked defaults from §6; time range is `now-6h` or a documented exemption
- [ ] host filtering uses the Host Label, never `instance`
