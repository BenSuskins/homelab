# Homelab Menu Bar

A macOS menu bar app for this repository: see the state of the three
dispatchable workflows, start or cancel them, see and squash-merge open pull
requests, and jump to Homepage / Actions / the repo.

```
⚙  ← glyph: worst-of (⚠ failed > ◐ running > ⚙ ok)
┌──────────────────────────────┐
│ Update      ✓ passed · 2h ago│  [▶]
│ Terraform   ⏸ awaiting appr… │
│ Clean       ◐ running · 3m 12s  [■]
│ ──────────────────────────── │
│ Open PRs (1)                 │
│  #141 chore(deps): ansible…  │  [Merge]
│ ──────────────────────────── │
│ Homepage ↗  Actions ↗  Repo ↗│
│ Updated 1m ago  Refresh  Settings  Quit
└──────────────────────────────┘
```

The platform-neutral half of this app now lives in
[`../homelab-core`](../homelab-core), shared with
[`../homelab-ios`](../homelab-ios). What is left here is the macOS half: the menu
views, the settings window, the login item, and `gh`.

## Requirements

The [GitHub CLI](https://cli.github.com), authenticated:

```bash
gh auth status   # needs the `repo` scope
```

The app holds no token of its own — every call shells out to `gh`, so
`gh auth login` is the only credential management there is. It searches `PATH`
and then Nix, Homebrew and `/usr/local` explicitly, because a GUI app launched
from Finder does not inherit your shell's `PATH`.

## Build

```bash
make test      # both packages: HomelabCore, then this one
make bundle    # .build/Homelab.app
make install   # copy to /Applications
make run       # build and launch without installing
```

`make test-core` alone is the fast red/green loop, since that is where the logic
is. The contract tests here are excluded by name:

```bash
swift test --skip Contract    # fakes only, no network
swift test --filter Contract  # real `gh`, read-only
```

## Settings

**Settings** in the menu footer opens a standard settings window. It holds one
option today — **Launch at login** — and its sections are where anything else
goes.

Launch at login registers with `SMAppService`, so the entry appears under System
Settings → General → Login Items like any other app.

`make bundle` ad-hoc signs, so every build carries a different signature and
macOS can drop the registration on reinstall. The app re-asserts it at launch
whenever you asked for it and the system says otherwise, so a rebuild does not
silently stop it starting. The one state it will not override is
`requiresApproval` — you switched it off in System Settings by hand, and only
you can switch it back on there.

## Design

Data flows one way, and every layer above the process boundary is a pure
function of the layer below:

```
GhCommandTransport        ← the only impure thing on this path; spawns `gh`
      ↓ Data
GitHubClient              ← decodes, maps onto domain types
      ↓ WorkflowRunSummary / PullRequestSummary
AppState                  ← @Observable, owns the polling loop
      ↓ StatusSnapshot    ← immutable; also what gets cached to disk
MenuView
```

Everything above `GhCommandTransport` is now in `HomelabCore`. `StatusSnapshot`
is the seam. It answers every question the view can ask — what colour a row is,
whether its button is enabled, what the subtitle says — so the view holds no
logic and the logic needs no view to test.

`LoginItemControlling` is the other process boundary — `SMAppService` behind a
protocol, faked the same way, so the reconcile-at-launch logic is tested without
touching your real login items.

Tests fake `GitHubTransport` in the core package and `CommandRunner` here, so
decoding, mapping, snapshot construction and argv rendering all run for real. A
handful of read-only contract tests run the actual `gh` to catch the one thing a
fake cannot: `gh` changing its output.

### Deliberate choices

- **No confirmation on trigger.** The guard against a stray double-click is that
  `▶` is disabled while a run is open, backed by `concurrency` groups on the
  workflows and `use_lockfile` on the Terraform backends.
- **The app never approves a deployment.** Terraform parks at its
  `required_reviewers` gate; the row says so and links to the run, where the
  plan is. Approving a plan you cannot see is just a slower auto-apply.
- **Notify on failure only.** Success is expected and the glyph already reports
  it, so a notification always means something broke.
- **A run awaiting approval does not raise the glyph or tighten polling.** It
  will sit there until a human acts.
- **Launch at login is stored twice.** The system status is the truth about
  what will happen at boot; the stored preference is the truth about what you
  asked for. Keeping both is what lets a reinstall be distinguished from a
  deliberate switch-off, and only the first one gets repaired.
- **The launch-at-login switch is never disabled.** `SMAppService.mainApp`
  reports `.notFound` in cases where registering nonetheless succeeds, so
  gating the control on the status produces a switch that refuses to move for
  no visible reason. The attempt decides, and a refusal says what macOS said.
- **Squash merge, always.** One commit on `main` per PR is one Update Homelab
  run is one line in the deploy log. Merging here deploys.
- **This app still holds no token.** That is now a property of
  `GhCommandTransport` rather than of the design, because the iOS app cannot
  have it — see ADR-0004.
