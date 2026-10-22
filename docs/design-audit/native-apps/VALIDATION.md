# Validation record

Date: 22 October 2026.

## HTML checks

The browser loads the self-contained HTML without external libraries or fonts.
The data and action results are sample values. No application API is used.
The Copy controls write sample text to the clipboard when the browser permits it.
External links open GitHub. The sample authorization code is never submitted.

| Check | Result |
|---|---|
| JavaScript syntax | `node --check` passes for the extracted inline script. |
| Screen states | 80 screen/state combinations render across all 17 screen families. |
| Default layout | No horizontal overflow in the preview, cards, notices, tables, or scroll regions for those 80 combinations. |
| Large text | All 17 families pass the overflow check at 200% text in dark appearance. iOS uses the 320-point width. The check includes the floating tab bar. |
| Widget families | All 14 declared variants render with Stale and No data states: 28 combinations. Each exposes an open action. |
| Themes | Light and dark previews inspected. Text token contrast measured in both themes. |
| Health coverage | Six hosts, 24 collapsed readings, 24 metric charts, 27 service rows, six service groups, and the visible availability chart. |
| Chart expansion | Each host opens CPU, memory, root disk, and load history. Only one host stays open. |
| Range changes | 1H, 6H, 24H, and 7D change the histories and peak summary. The expanded host stays open. The Logs range remains independent. |
| Missing host metrics | Host no data shows 5/6 reporting and four missing readings for AI. All 27 service rows remain available. |
| Liquid Glass | The tab bar floats over scrolling content. Account and back controls use the same material. Content rows and charts stay flat. |
| Final-row clearance | At the bottom of Health, the final service row ends about 53 pixels above the floating tab bar at 375 points. |
| Mac long list | The list scrolls inside a 500-pixel region. The full menu is about 616 pixels high. The footer remains outside the list. |
| PR description | Each selected PR opens its own body. PR #127 retains its number and title in the direct merge action and on Back. |
| Body states | Both platforms cover description, no description, loading, stale, error, and conflict states. Conflicting PRs have no merge button. |
| PR navigation | Back restores the list state and scroll position. The iOS Pull requests tab stays selected. |
| Direct actions | Run Terraform and merge PR #127 keep the current screen. iOS shows a sample Face ID result, then an accepted request. Mac Run Clean submits directly. No review screen exists. |
| Log search and detail | Search for “cache” shows the Grafana line. The row opens Grafana, its message, labels, and full raw JSON. |
| Sign-in recovery | Mac Sign in opens the code screen. Expired → Get a new code returns to Waiting. |
| Sign out | Keep signed in returns to Account. Sign out opens the sample sign-in screen. |
| Text contrast | Proposed light tertiary text on a raised surface measures 4.77:1. Proposed dark tertiary text measures 7.36:1. |
| Primary button | White text on the proposed blue action fill measures 5.87:1. |
| Local links | All local Markdown and HTML document targets exist. |
| Whitespace | `git diff --check` passes. |

The large-text check finds a clipped Done button in the Account header.
The repaired header places its title above the action row at 200% text.
The repeated check passes for all 17 families.

These checks measure HTML layout and sample behavior. They do not establish native accessibility compliance.
The 200% control approximates large text. It does not emulate native Dynamic Type.
The width control requests a preview width. A narrow browser pane can constrain the actual width.
The landscape and iPad options are design previews, not native device checks.

## Preview images

- [iOS Home](previews/ios-home.png)
- [Mac menu](previews/mac-menu.png)
- [iOS PR description](previews/ios-pr-description.png)
- [Health overview](previews/ios-health.png)
- [Health host charts](previews/ios-health-host.png)
- [Health services](previews/ios-health-services.png)

These are screenshots of the HTML proposal with sample data.
The capture view uses a shorter content region so the complete frame fits in the image.
It does not change the standard interactive preview.

## Remaining native checks

CoreSimulatorService refuses the connection during `simctl list devices booted`.
The generic iOS simulator build compiles the app and widgets. The installed iOS and Mac screens are not exercised.
Liquid Glass in the HTML is a CSS approximation. Native refraction, system materials, and scroll behavior require an iOS 26 device check.

The following checks remain:

- VoiceOver, native keyboard focus, actual hit regions, all Dynamic Type sizes, and system contrast preferences.
- Physical iPhone and iPad layouts, landscape, keyboard insets, and system sheet gestures.
- Launch, foreground return, and pull-to-refresh on each native tab.
- Device authentication and passcode fallback, including unavailable evaluation.
- Browser authorization, revoked sessions, Login Items, and Mac notification permission.
- Live logs, background behavior, action transport failures, and real deployment progress.
- Every WidgetKit family under system tint, redaction, and refresh scheduling.

The shared core suite passed 157 tests. The iOS app and widget target compile for the generic simulator. The Mac app builds with SwiftPM.
No CI, TestFlight, installed-app, or production behavior claim follows from the HTML checks.

## Local preview access

The preview server listens on loopback only.
Its route allowlist contains index.html, AUDIT.md, VALIDATION.md, and DESIGN.md.
It serves no repository directory listing or other file.
Automatic approval review rejects an earlier proposal to serve the complete repository.
The restricted server resolves that concern.

## Workboard

The Workboard status workflow is read, but no Workboard tools are available in this session.
No project status is posted. Connect the Workboard MCP server to record the audit there.


The 157 passing core tests include the pull request description read through the fake transport.
The iOS build uses the installed Xcode toolchain and simulator SDK. The current simulator service prevents launch-level checks.
