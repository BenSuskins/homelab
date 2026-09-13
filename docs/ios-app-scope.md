# iOS companion app: scope

> **Status: built.** Phases 0–7 landed together. This is kept as the reasoning
> behind the shape of `apps/`, and for the roadmap past v1 at the end, which is
> not built. The two decisions it settled are ADR-0004 and ADR-0005.

`apps/homelab-menubar/` drives this repository's three Dispatchable Workflows,
lists and squash-merges open pull requests, and links out to Homepage. This
document scopes an iOS companion that starts at parity with it and grows into a
command centre — service health, logs, metrics, SSH — reachable over the
existing Tailscale Subnet Router.

## What actually blocks a port

One thing, and it is the macOS app's central design principle: *the app holds no
token — every call shells out to `gh`*. iOS has no subprocess spawning, so
`GitHubCommandLineRunner` cannot cross the platform boundary and the iOS app
must hold a credential of its own. That is ADR-0004, and it is the only genuine
conflict. Everything else is mechanical.

The mechanical part is unusually cheap because of how the macOS app is already
factored. Five of `GitHubClient`'s six calls are `gh api <REST path>` —
literally a method, a path, and some fields. Only `openPullRequests()` reaches
for `gh pr list --json`, whose output shape (`author.login`, `isDraft`,
`mergeable` as `MERGEABLE`/`CONFLICTING`) is `gh`'s own rather than the REST
API's. That matters more than it looks: REST's `/pulls` list endpoint does not
return `mergeable` at all — it exists only on the single-PR endpoint, computed
lazily — so a naive REST port would silently lose the field
`PullRequestSummary.canMerge` depends on, and every PR row would offer a merge
button that might fail.

GraphQL resolves it. One `pullRequests` query returns exactly the shape
`MergeReadiness(mergeableField:)` already decodes, and both platforms can issue
it — `gh api graphql` on macOS, a POST to `api.github.com/graphql` on iOS.
Rewrite that one call and every GitHub interaction becomes transport-neutral,
with no change to the domain types or the tests that cover them.

### Audit of `Sources/HomelabMenuBarCore/`

| Portable as-is | macOS-only | Needs work |
|---|---|---|
| all of `Domain/` | `Support/LoginItemService.swift` (`SMAppService`) | `GitHub/CommandRunner.swift` (`Process`) |
| `Menu/MenuSnapshot.swift`, `PollingSchedule.swift` | `App/AppState+LaunchAtLogin.swift` | `GitHub/GitHubFailure.swift` — messages are `gh`-shaped |
| `Menu/RunStatusPresentation.swift` (SwiftUI `Color`) | `Menu/MenuView.swift`, `RunRowView`, `PullRequestRowView` | `GitHub/GitHubClient.swift` — one call is not REST |
| `Support/SnapshotCache.swift`, `RelativeTime.swift` | `Settings/SettingsView.swift` (`SettingsLink`, `NSApp`) | `Support/FailureNotifier.swift` — compiles on iOS, but see ADR-0005 |
| `App/AppState.swift`, `+Refresh`, `+Actions` | | |

## Settled parameters

- **Distribution** — Apple Developer Programme and TestFlight (£79/yr). The free
  personal-team route expires a provisioning profile every seven days and
  forecloses APNs entirely; a PWA behind Traefik reuses none of the Swift.
- **Auth** — GitHub OAuth device flow, token in the Keychain (ADR-0004).
- **v1** — workflow and pull-request parity, plus a service health screen and a
  home-screen widget.
- **Layout** — extract a shared `HomelabCore` package rather than duplicate the
  domain.

## Sequence

Eight phases. They were planned as one pull request each and delivered as one;
the phase boundaries survive as the order to read the diff in. Phases 0 and 1
must be indistinguishable from `main` when you run the macOS app.

### Phase 0 — extract `apps/homelab-core/`

A new SwiftPM package, `platforms: [.macOS(.v15), .iOS(.v18)]`, exposing target
`HomelabCore`: `Domain/`, `GitHub/`, `StatusSnapshot.swift` (renamed from
`MenuSnapshot.swift`, since it is no longer a menu's),
`PollingSchedule.swift`, `RunStatusPresentation.swift`, `SnapshotCache.swift`,
`RelativeTime.swift`, and `AppState{,+Refresh,+Actions}.swift`.

`apps/homelab-menubar/` keeps `HomelabMenuBarCore` for the macOS-specific half —
the three menu views, `SettingsView`, `LoginItemService`,
`AppState+LaunchAtLogin`, `GitHubCommandLineRunner` — depending on the core by
relative path. Tests split the same way: `AppStateTests`, `GitHubClientTests`,
`StatusSnapshotTests`, `Fixtures/Samples.swift`, `LaunchAtLoginTests` and
`FakeLoginItemService` move — the launch-at-login *logic* is platform-neutral,
only `SMAppService` is not. `FakeCommandRunner` and the contract tests stay,
because the contract tests run real `gh`.

Members that now cross a module boundary become `public` — chiefly `AppState`'s
`internal(set)` properties and the `client`/`cache`/`notifier` dependencies.

Done when `make test` and `make bundle` behave exactly as they do today. No
behaviour change is the whole point of doing it as its own pull request.

### Phase 1 — transport seam and GraphQL normalisation

Replace `CommandRunner` as *the* seam with something not shaped like a shell:

```swift
public struct GitHubRequest: Sendable, Equatable {
    public enum Body: Sendable, Equatable {
        case rest(method: String, path: String, fields: [String: String])
        case graphQL(query: String, variables: [String: String])
    }
    public let body: Body
}

public protocol GitHubTransport: Sendable {
    func send(_ request: GitHubRequest) async throws(GitHubFailure) -> Data
}
```

`GhCommandTransport` (macOS) renders a request into the argv `GitHubClient`
builds today and hands it to the existing `CommandRunner`, so
`GitHubCommandLineRunner`, its `PATH` search and `FakeCommandRunner` all survive
untouched. `URLSessionTransport` (shared) sends the same request to
`api.github.com` with a bearer token from a `TokenProviding` protocol.

`GitHubFailure` generalises to `transportUnavailable`, `notAuthenticated`,
`requestFailed(status:message:)` and `malformedResponse`. The `gh`-specific
mapping — exit code 4, the "gh auth login" string match — moves into
`GhCommandTransport`, and `displayMessage` stops naming `gh` unless the gh
transport supplied the text.

### Phase 2 — iOS scaffold

`apps/homelab-ios/Homelab.xcodeproj` is committed and is the source of truth:
the app target, the widget extension, the App Group, and the local package
dependency all live in it. Add `ios-build` to the Makefile.

This started as XcodeGen with a gitignored project, on the reasoning that a
`.xcodeproj` is a merge-conflict machine. That was reversed once it emerged
that TestFlight deployment goes through **Xcode Cloud**, which discovers the
project by scanning the repository — a generated one is not there to be found
when you set the workflow up. `project.yml` seeded the committed project and was then deleted.

Add `.github/workflows/apps.yml` on `paths: ['apps/**']`, `runs-on: macos-15` —
the mirror image of the `paths-ignore` blocks ADR-0003 describes. Nothing builds
or tests the Swift code in CI today, and a second app is where that stops being
tolerable. The `self-hosted` runner is Linux and cannot build iOS.

No change is needed to `update.yml` or `build-mcp-arr.yml`: their
`paths-ignore: ['apps/**']` already covers the two new directories.

### Phase 3 — device-flow auth

`POST github.com/login/device/code`, show the user code, then poll
`POST github.com/login/oauth/access_token` with
`grant_type=urn:ietf:params:oauth:grant-type:device_code`, honouring
`authorization_pending` and `slow_down`. A `TokenStore` protocol with a
`KeychainTokenStore` using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and an
access group shared with the widget, faked in tests like every other boundary.

`LAContext` gates `trigger`, `cancel` and `merge`. Reads stay ungated. See
ADR-0004 for why, and for the scope caveat.

### Phase 4 — parity UI

Three tabs over the same `AppState`. Runs (the three Run Rows, with
`RunStatusPresentation` already supplying symbol, tint and label, so the row is
a layout exercise rather than a logic one), Pull Requests
(swipe-to-squash-merge, `canMerge` gating unchanged), and Health. The quick
links sit in a section of the Runs tab rather than a tab of their own.

Two lifecycle differences need handling rather than hoping:

- `restartPolling()` only runs while foregrounded, so drive it from
  `scenePhase` — `.active` starts, `.background` stops — and add
  `.refreshable`.
- `FailureNotifier` is deliberately not wired up. See ADR-0005.

`SnapshotCache.defaultFileURL()` gains an App Group container option so the
widget reads the same cached Menu Snapshot.

### Phase 5 — health screen

One data source: **Prometheus on `192.168.0.203:9090`, direct over the tailnet.**
Its Service Entry in `group_vars/all.yml` is `secured: true, proxied: true`, so
`prometheus.suskins.co.uk` sits behind Authelia — but the host port itself is
unauthenticated and the Subnet Router advertises `192.168.0.0/24`, so a
tailnet-connected phone reaches it with no auth dance. Gatus would otherwise be
the obvious source, but its own `security.oidc` block makes its API awkward for
a native client; Prometheus sidesteps that and gives one client for both the
health grid and the metrics work in the roadmap.

Per-service up and down comes from `gatus_results_endpoint_success`, which
`CONTEXT.md` already flags as load-bearing for the `gatus-endpoint-down` rule.
Host tiles come from `node_*`. Both obey ADR-0001: filter and group by the Host
Label, never `instance`, and never use `up` for liveness, because those series
are Remote-Written and produce no `up`. Lay the screen out on the
`Status → Topic → Detail` grammar in `docs/grafana-dashboard-style.md` so the
phone reads like the dashboards.

**Two independent failure domains share one app.** GitHub works anywhere;
Prometheus only on the tailnet. Off-tailnet must degrade to "not connected to
the tailnet" on that screen alone — never a blocking spinner, never a global
error banner over the Runs tab.

### Phase 6 — widget

`.systemSmall` and `.systemMedium`: the Glyph State, the worst Run Row, and its
subtitle. `MenuSnapshot.glyph` and `RunRow.subtitle(now:)` already compute all of
it. `getTimeline` does its own light fetch and falls back to the App Group
cache. It requests a fifteen-minute refresh and iOS treats that as a suggestion,
which is exactly why ADR-0005 exists.

### Phase 7 — docs

Amend ADR-0003 (the app*s* live here; the `paths-ignore` coupling now guards
three directories). Update `CONTEXT.md`: the "Menu Bar App" section becomes
"Apps", **Menu Snapshot** is renamed **Status Snapshot** now that it is not a
menu's, and **Transport**, **Token Store** and **Health Grid** are added. Write
`apps/homelab-ios/README.md`.

## Roadmap past v1

**Service directory — ~2 days, and the enabler for everything below it.** The
app cannot see `docker_services`; it is Ansible runtime state.
`tasks/other/generate_readme.yml` already renders a localhost template from
`all_services`, so copy that pattern into
`tasks/other/generate_services_json.yml` plus a `config/readme/services.json.j2`,
commit the output by hand alongside `docs/ARCHITECTURE.md`, and read it from the
app via the GitHub contents API. No new infrastructure, no new auth, and it
works off-tailnet. This gives the command-centre screen its service list, its
deep links, and gives logs and SSH their target pickers.

**Log viewer — implemented in the iOS app.** Loki is already on
`192.168.0.203:3100` with `auth_enabled: false` and thirty-day retention. Alloy
pushes container logs via `loki.source.docker`; there is no journal source, so
host-level logs are not in Loki today. The Logs tab uses
`/loki/api/v1/query_range` for history and `/loki/api/v1/tail` over
`URLSessionWebSocketTask` for live tail. Alloy adds the canonical Friendly Name
as the `host` label, and the app provides host and container pickers instead of
a free-text LogQL box.

**Metrics — implemented in the iOS app.** `PrometheusClient` gained
`rangeQuery`, and the Health tab is now charts over a selectable Metric Window
rather than a snapshot: per-host CPU, memory, disk and load, plus how many
endpoints were failing across the window. Every tile reads the last point of the
line drawn beneath it, so one fetch feeds both. The cheap alternative — Grafana
in a `WKWebView` with `&kiosk` — was not taken: Grafana is `secured: true`, so
you meet an Authelia login inside the webview, and the dashboards are laid out
for a desktop. Per-*container* metrics are still not built.

**Run history — implemented in the iOS app.** The workflow-runs endpoint is
asked for a page rather than a row, which cost no extra calls, and the home
screen draws duration bars, pass rate, median duration and a cross-workflow
timeline from it. The deep page is fetched at most every two minutes; a poll
during an active run asks for one run.

**SSH — 2–3 weeks, highest risk.** SwiftNIO SSH, or Citadel on top of it. Build
a *command palette, not a terminal*: `docker ps`, `docker logs --tail`,
`docker restart`, `df -h`, `uptime` over exec channels with structured output. A
VT100 on a phone keyboard is a worse tool than five buttons, and SwiftTerm can
add a real terminal later if the palette proves insufficient. Generate an
Ed25519 key in-app, store it under `.biometryCurrentSet`, and distribute the
public key through the repository rather than by hand. Give it a dedicated
non-sudo user or a `command=`-restricted `authorized_keys` entry — the phone
should not carry a key that can `sudo` on six hosts.

**Push notifications — a separate project.** A webhook receiver container, a
public endpoint GitHub can reach, and an APNs auth key. Worth revisiting once
the widget has been lived with and found insufficient, and not before.

## Costs, stated plainly

Pros:

- One source of truth for the domain; the macOS app inherits a better-tested
  core for free.
- The existing architecture was built for this. Moving the seam up one level is
  small and mechanical.
- Tailscale already solves remote access, so the hard networking problem is
  done.
- A health grid is something a phone is genuinely better at than a menu bar.

Cons:

- Phase 0 churns a working, tested app for a benefit invisible until Phase 4.
- £79/yr, indefinitely, for a personal app.
- The iOS app holds a broadly-scoped credential the macOS app avoided
  (ADR-0004).
- Widget refresh is best-effort and cannot carry anything time-critical
  (ADR-0005).
- Two failure domains in one app, only one of which works off the tailnet.

Roughly six to eight focused sessions to the end of Phase 7.

## Unrelated finding

Loki's Service Entry in `tasks/docker/loki.yml` sets `host: "loki.{{ domain }}"`
and `secured: false` but never sets `proxied`. The Traefik template filters on
`selectattr('proxied', 'defined') | selectattr('proxied')`, so that hostname is
not a live route and Loki is only reachable on `192.168.0.203:3100` — which,
with `auth_enabled: false`, means unauthenticated to anything on the LAN or the
tailnet. That is a defensible posture, and it is the posture Phase 5 and the log
viewer both rely on — Prometheus is reached the same way, for the same reason.

The problem is the `host:` key, which does nothing today and is one word away
from doing a great deal: adding `proxied: true` to that entry — the natural
thing to do if you wanted to reach logs from a browser — would publish thirty
days of logs from every host through Traefik with `secured: false`, in a
one-line diff that looks like enabling a route. Drop the dead `host:` key, or
set `secured: true` alongside it so the accident is not available. This predates
the app and should be fixed on its own.
