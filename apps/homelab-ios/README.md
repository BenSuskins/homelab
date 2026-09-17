# Homelab (iOS)

The phone half of [`../homelab-menubar`](../homelab-menubar): the same three
Dispatchable Workflows, the same pull request list, plus service health, logs,
and three home-screen widgets.

```
┌──────────────────────────────┐   Widgets
│ Homelab                   ◍  │   ┌──────────────┐ ┌──────────────┐
│ ┌──────────────────────────┐ │   │ ● Homelab    │ │ ● Services   │
│ │ ● All workflows green    │ │   │ Update       │ │ 27/27        │
│ │ Updated 2m · 7 deploys   │ │▶  │ passed · 2h  │ │ all up       │
│ └──────────────────────────┘ │   └──────────────┘ └──────────────┘
│ [96% pass][7 deploys][3 PRs] │
│ WORKFLOWS                    │   Workflows · Service health ·
│ ┌ ● Update      passed  ▶ ┐  │   Pull requests, each at several
│ │ ▁▃▂▅▂▁▃▂▁▄▂▁▃  96% · 4m │  │   sizes plus the lock screen.
│ └─────────────────────────┘  │
│ RECENT ACTIVITY              │
├──────────────────────────────┤
│  Home · PRs · Health · Logs  │
└──────────────────────────────┘
```

## What is on each screen

- **Home** — the status hero (is anything wrong), a strip of numbers, then one
  card per workflow carrying its last twenty runs as duration bars, its pass
  rate and its median duration. Underneath, the runs of all three interleaved
  into one timeline. The trigger and cancel buttons are on the cards.
- **Pull requests** — split into what will merge cleanly and what will not, with
  the squash button on the row rather than behind an invisible swipe. The label
  says what merging does: it deploys.
- **Health** — a window picker (1H/6H/24H/7D) scoping every chart at once, the
  status strip, how many endpoints were failing over that window, then one card
  per host. Tapping a host opens its CPU, memory, disk and load charts.
- **Logs** — host and container filters as menus, a level filter carrying its
  own counts, a search field, an explicit live-tail toggle, and lines shown
  taken apart rather than printed: the level, the container's own timestamp,
  the message, then the remaining fields as chips. Tapping a line opens every
  field, every stream label, both timestamps and the raw line.
- **Account** — behind the avatar in the top right, on every screen. Sign-out
  lives here rather than under the deploy buttons.

Nothing on any screen is a system list or a form. The palette, the type scale
and the spacing come from `HomelabCore/Design`, shared with the widgets so the
two cannot drift.

## What it needs before it will run

1. **A GitHub OAuth app.** <https://github.com/settings/developers> → New OAuth
   App → tick **Enable Device Flow**. Put the client ID in
   `HomelabConfiguration.iOS`, in the shared package. There is no client secret
   and no server: that is why device flow was chosen (ADR-0004). The sign-in
   button stays disabled until you replace the placeholder.
2. **An Apple Developer Programme membership**, for the App Group and a
   provisioning profile that lasts a year rather than a week.
3. **Tailscale on the device**, for the Health and Logs tabs. Runs and pull
   requests work from anywhere.

## Build

```bash
cd ../homelab-menubar
make ios-build       # xcodebuild against the simulator SDK (compile only)
```

Or just open `Homelab.xcodeproj`, set your team on both targets, and run.

The project file is **committed and is the source of truth** — change targets in
Xcode, not in a spec. It was XcodeGen-generated and gitignored to begin with,
until Xcode Cloud turned out to need a project it can find by scanning the
repository; the spec seeded this one and was then deleted.

There is no `make ios-test`. Every testable decision lives in `HomelabCore` and
is covered by `make test-core`; this target is views and wiring, so a clean
compile is what there is to prove.

## How it differs from the macOS app

The two share `HomelabCore` — domain types, `GitHubClient`, `StatusSnapshot`,
`AppState`, `Session`, the polling schedule — and since ADR-0004's amendment
they share the sign-in flow and the OAuth client too. Two things still differ:

- **Writes are behind Face ID.** Trigger, cancel and merge all deploy. Reads are
  not gated — a status glance should not cost a prompt.
- **There are no notifications.** A backgrounded iOS app is suspended within
  seconds, so the polling loop stops and a local notification could only fire
  while you were already looking at the app. The widgets are the ambient signal
  instead, and they are *not* an alerting mechanism: iOS treats the refresh
  interval as a hint and may honour it hours late. **ADR-0005.**

## The widgets

Three of them, each in the gallery under its own name:

| Widget | Shows | Families |
|---|---|---|
| Workflows | The three Run Rows and the worst of them | small, medium, large, circular, rectangular, inline |
| Service health | How many endpoints are up, and which are not | small, medium, rectangular, inline |
| Pull requests | Open count, how many are ready, the top three | small, medium, rectangular, inline |

They share one App Group snapshot, so every refresh writes back both the runs
and the pull requests — a fetch that saved only its own half would delete the
other widget's data.

Out of the box they render from the cache the app writes while it is
foregrounded, because the app and the extension are separate app IDs and the
extension cannot read the app's Keychain item. They are therefore only as fresh
as your last visit, and say so with a clock glyph.

To let them fetch on their own, add a `keychain-access-groups` entitlement of
`$(AppIdentifierPrefix)co.uk.suskins.Homelab` to both targets and set the
literal team-prefixed value in `HomelabConfiguration.iOS.keychainAccessGroup`.
Either way they stay ambient indicators, not alerts — iOS decides when a
timeline actually refreshes (**ADR-0005**).

Service health is the exception that cannot fetch at all most of the time:
Prometheus is tailnet-only, so that widget is drawing what the app last read
unless the phone happens to be on the tailnet when iOS wakes it.

## The Health tab

Reads Prometheus directly on `192.168.0.203:9090` over the tailnet, not through
`prometheus.suskins.co.uk`, which sits behind Authelia. Service state comes from
`gatus_results_endpoint_success` — the same series the `gatus-endpoint-down`
alert rule uses — and the host charts from `node_*`.

Every number on the screen is the last point of a line drawn directly
underneath it. That is one fetch rather than two, and it makes a tile
disagreeing with the chart beside it impossible rather than merely unlikely.
The window picker owns the Prometheus `step` and `rate()` interval for each
span, so a 7-day chart is not sampled as if it were an hour.

It obeys `docs/adr/0001-host-label-canonical-for-dashboards.md`: grouped by the
Host Label, never `instance`, and never using `up` for liveness, because those
series are Remote-Written by Alloy and produce no `up`.

GitHub and Prometheus are independent failure domains, so off the tailnet the
Health and Logs tabs alone say "not connected" and the other two keep working.

## The Logs tab

Reads container logs from Loki directly on `192.168.0.203:3100` over the
tailnet. It supports a one-hour history by default, host and container filters,
and an explicit live-tail mode. Loki receives the same Friendly Name `host`
label that Prometheus uses. The viewer does not include host journal logs.

Lines are read apart by `LogRecord`, because `loki.source.docker` ships
container stdout verbatim — there is no level label to read, and every container
writes its own format. Three shapes are recognised: JSON, logfmt, and plain
text with a leading timestamp and a bracketed level. From whichever it is, the
row shows the level, the timestamp the container wrote, the message, and the
remaining fields as chips; the rest is one tap away on the detail sheet, which
also carries the raw line in case the parse got something wrong.

A level the line declared (`level=warn`, `"severity":"ERROR"`, a leading
`[info]`) is treated differently from one guessed out of the words in the line:
the detail sheet says which it is, and only a declared level is safe to filter
on. Nothing is ever dropped for being misclassified — the level filter narrows
what is shown, and the counts on the chips say what it is narrowing from.

Two things about this screen were broken and are worth not re-breaking:

- The unfiltered selector is `{container=~".+"}`. `URLComponents.queryItems`
  does not escape `+`, and Go's `url.ParseQuery` reads a bare `+` as a space, so
  Loki was being asked for `{container=~". "}` and answering — correctly — with
  nothing. Both clients now build their query strings through `QueryEncoding`.
- `/loki/api/v1/tail` answers with `{"streams": [...]}`, not the `status`/`data`
  envelope the query endpoints use. Decoding a tail frame as a query response
  fails on every frame, which is what made Live light up and show nothing.
