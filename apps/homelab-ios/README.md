# Homelab (iOS)

The phone half of [`../homelab-menubar`](../homelab-menubar): the same three
Dispatchable Workflows, the same pull request list, plus a service health screen
and a home-screen widget.

```
┌──────────────────────────┐   Widget (small)
│ ⚙ Homelab                │   ┌──────────────┐
│                          │   │ ⚙ Homelab    │
│ ✓ Update    passed · 2h  │▶  │ Update       │
│ ⏸ Terraform awaiting…    │   │ passed · 2h  │
│ ◐ Clean     running 3m12s│■  └──────────────┘
├──────────────────────────┤
│  Runs  · PRs · Health    │
└──────────────────────────┘
```

## What it needs before it will run

1. **A GitHub OAuth app.** <https://github.com/settings/developers> → New OAuth
   App → tick **Enable Device Flow**. Put the client ID in
   `Sources/HomelabApp/AppConfiguration.swift`. There is no client secret and no
   server: that is why device flow was chosen (ADR-0004). The sign-in button
   stays disabled until you replace the placeholder.
2. **An Apple Developer Programme membership**, for the App Group and a
   provisioning profile that lasts a year rather than a week.
3. **Tailscale on the device**, for the Health tab only. Runs and pull requests
   work from anywhere.

## Build

```bash
cd ../homelab-menubar
make ios-generate    # xcodegen → Homelab.xcodeproj (never committed)
make ios-build       # xcodebuild against the simulator
```

Then open `Homelab.xcodeproj`, set your team on both targets, and run.

There is no `make ios-test`. Every testable decision lives in `HomelabCore` and
is covered by `make test-core`; this target is views and wiring, so a clean
compile is what there is to prove.

## How it differs from the macOS app

The two share `HomelabCore` — domain types, `GitHubClient`, `StatusSnapshot`,
`AppState`, the polling schedule. Three things genuinely differ:

- **It holds a token.** macOS shells out to `gh` and holds no credential; iOS
  cannot spawn a subprocess, so it stores an OAuth token in the Keychain
  (`WhenUnlockedThisDeviceOnly`, so a locked phone cannot be read and the token
  never reaches an iCloud backup). `GhCommandTransport` and
  `URLSessionTransport` are the two sides of that seam. **ADR-0004.**
- **Writes are behind Face ID.** Trigger, cancel and merge all deploy. Reads are
  not gated — a status glance should not cost a prompt.
- **There are no notifications.** A backgrounded iOS app is suspended within
  seconds, so the polling loop stops and a local notification could only fire
  while you were already looking at the app. The widget is the ambient signal
  instead, and it is *not* an alerting mechanism: iOS treats the fifteen-minute
  refresh as a hint and may honour it hours late. **ADR-0005.**

## The widget refreshes from cache until you share a Keychain group

Out of the box the widget renders from the App Group cache the app writes when
it is foregrounded, because the app and the extension are separate app IDs and
the extension cannot read the app's Keychain item. It is therefore only as fresh
as your last visit to the app.

To let it fetch on its own, add a `keychain-access-groups` entitlement of
`$(AppIdentifierPrefix)co.uk.suskins.Homelab` to both targets and set the literal
team-prefixed value in `AppConfiguration.keychainAccessGroup` **and**
`WidgetSettings.keychainAccessGroup`. Either way it stays an ambient indicator,
not an alert — iOS decides when a timeline actually refreshes.

## The Health tab

Reads Prometheus directly on `192.168.0.203:9090` over the tailnet, not through
`prometheus.suskins.co.uk`, which sits behind Authelia. Service state comes from
`gatus_results_endpoint_success` — the same series the `gatus-endpoint-down`
alert rule uses — and host tiles from `node_*`.

It obeys `docs/adr/0001-host-label-canonical-for-dashboards.md`: grouped by the
Host Label, never `instance`, and never using `up` for liveness, because those
series are Remote-Written by Alloy and produce no `up`.

GitHub and Prometheus are independent failure domains, so off the tailnet the
Health tab alone says "not connected" and the other two keep working.
