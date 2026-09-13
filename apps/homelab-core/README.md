# HomelabCore

Everything both apps agree on: the domain types, the GitHub client, the
`StatusSnapshot` they render, the polling schedule, and the Prometheus client
behind the iOS health screen.

```bash
swift test        # or `make test-core` from ../homelab-menubar
```

Consumed by [`../homelab-menubar`](../homelab-menubar) (macOS) and
[`../homelab-ios`](../homelab-ios), both by relative path.

## The seam

`GitHubClient` builds a `GitHubRequest` — a method, a path, some fields, or a
GraphQL query — and hands it to a `GitHubTransport`. It has no idea which one.

```
GitHubClient
     ↓ GitHubRequest
GitHubTransport            ← the only impure thing on this path
     ├─ GhCommandTransport  (macOS: spawns `gh`, holds no credential)
     └─ URLSessionTransport (iOS: bearer token from the Keychain)
     ↓ Data
GitHubClient               ← decodes, maps onto domain types
     ↓ WorkflowRunSummary / PullRequestSummary
AppState                   ← @Observable, owns the polling loop
     ↓ StatusSnapshot      ← immutable; also what gets cached to disk
the views
```

`StatusSnapshot` answers every question a view can ask — what colour a row is,
whether its button is enabled, what the subtitle says — so the views hold no
logic and the logic needs no view to test. It was `MenuSnapshot` while there was
only a menu.

Tests fake the transport, which means decoding, mapping and snapshot
construction all run for real. The only thing stubbed is the network.

## Why pull requests go over GraphQL

Five of the six calls are plain REST paths. `openPullRequests()` is not, and it
is worth knowing why before anyone "simplifies" it: **REST's `/pulls` list
endpoint does not return `mergeable`.** It exists only on the single-PR
endpoint, computed lazily. Switching to REST would quietly lose the field
`PullRequestSummary.canMerge` is built on and offer merge buttons that fail.

GraphQL returns it as `MERGEABLE`/`CONFLICTING`/`UNKNOWN`, which is exactly what
`MergeReadiness` decodes, and `gh api graphql` issues the same query, so both
transports get identical bytes.

## Platform boundaries

Nothing here imports AppKit, `ServiceManagement`, or `Process`. Three things are
protocols precisely so the platform-specific half can live in the app target:

| Protocol | macOS | iOS |
|---|---|---|
| `GitHubTransport` | `GhCommandTransport` | `URLSessionTransport` |
| `LoginItemControlling` | `LoginItemService` (`SMAppService`) | `UnsupportedLoginItemService` |
| `WriteAuthorising` | `AlwaysAuthorised` | `BiometricWriteAuthorisation` |

`FailureNotifying` is a fourth, with a deliberate asymmetry: the concrete
`FailureNotifier` lives in the macOS target even though `UserNotifications`
compiles on iOS, so the iOS app *cannot* wire up a notifier that would never
fire. See ADR-0005.
