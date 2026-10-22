# Homelab native app UI and UX audit

Date: 22 October 2026. Scope: the iOS app, iPad layouts, all widget families, and the macOS menu bar app.

The main opportunities are clear status, readable text, accessible controls, and local request feedback.
Keep the existing navigation structure. The selected visual direction is a flat dashboard with compact rows and charts.
Use iOS 26 Liquid Glass for floating navigation and toolbar controls.

Open the [HTML proposal](index.html). Read the [design rules](../../../DESIGN.md).

## Evidence and limits

This is a source-led audit of every reachable screen family in the current checkout.
The source inventory includes all SwiftUI views, sheets, menus, app roots, and widget declarations.
The iOS target supports iPhone and iPad. Its deployment target is iOS 18. The Mac package targets macOS 15.

The HTML uses sample data. It does not connect to GitHub, Loki, Prometheus, or a live account.
Native screenshots and physical device tests are not part of the evidence.
`xcrun simctl list devices booted` fails because CoreSimulatorService refuses the connection in this session.
No native UI test target or deterministic demo entry point appears in the app source inventory.
The current Mac app is inspected from source; its live menu and system permission dialogs are not exercised.

Source findings below are reproducible code observations. Proposed behavior is a design decision, not an existing feature.
Keyboard, VoiceOver, native Dynamic Type, system sheet gestures, device authentication, and installed-build refresh remain native checks.
Workboard tools are unavailable. The project context and status cannot be read or updated in this session.

## Basis and fit

The requested [Apple Design skill](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md) informs feedback, spatial continuity, typography, and motion reduction.
The requested [UI/UX Pro Max skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) informs accessibility, state clarity, touch controls, and platform conventions.
The installed copies and the linked repositories are inspected.

UI/UX Pro Max searches cover a product direction and the detected SwiftUI stack.
The first design-system result returns a marketing layout. A narrower query returns an operations landing page.
Neither layout fits a native utility. Do not persist either generated system.
Use the verified SwiftUI text-size guidance and the general accessibility checklist.
Keep the existing system font and palette roles. The restrained native direction is a project-specific synthesis.

The existing [Grafana guide](../../grafana-dashboard-style.md) remains valid for Grafana.
Use its status-first structure and common severity meaning. Do not apply its panel geometry to native apps.

## Priorities

P1 means a misleading state or an obstacle to a core task.
P2 means a clarity, consistency, or efficiency improvement.
No production safety or security severity is implied by these design priorities.

| ID | Priority | Finding and source evidence | Proposed improvement |
|---|---|---|---|
| D01 | P1 | [Typography.swift](../../../apps/homelab-core/Sources/HomelabCore/Design/Typography.swift) uses fixed font sizes. [RootView.swift:17](../../../apps/homelab-ios/Sources/HomelabApp/RootView.swift#L17) caps Dynamic Type. Log chips use 9–10 point text. | Use semantic text styles and scaled metrics. Let rows wrap. Stack tiles and tables at accessibility sizes. Remove the cap. |
| D02 | P1 | [Palette.swift](../../../apps/homelab-core/Sources/HomelabCore/Design/Palette.swift) uses low-contrast tertiary text for essential metadata. | Strengthen text tokens in both themes. Keep the accent and surface hierarchy. Measure every tinted text pair. |
| D03 | P1 | [Components.swift:290](../../../apps/homelab-ios/Sources/HomelabApp/Components.swift#L290) gives IconButton a 30 × 30 frame. The profile button has a 28 × 28 frame. Several chips lack expanded hit regions. | Define 44 × 44 point minimum hit areas on iOS. Verify actual hit areas on a device. Add target-specific labels. |
| D04 | P1 | [HomeView.swift:106](../../../apps/homelab-ios/Sources/HomelabApp/HomeView.swift#L106) falls through to “All workflows green” for missing or never-run data. Health can show “all nominal” with no hosts. | Give unknown and loading their own state. Use positive labels only when observations support them. |
| D05 | P1 | [PullRequestsView.swift:17](../../../apps/homelab-ios/Sources/HomelabApp/PullRequestsView.swift#L17) treats an empty list as no open pull requests. It does not render request failure. Health and Logs render unreachable states but omit other monitor failures. | Model each resource state. Show errors and retry controls on the affected screen. Keep stale content with its age. |
| D06 | P1 | Workflow cards and pull request cards combine an outer `onTapGesture` with inner write buttons. Mac rows use the same pattern. | Use separate Link and Button controls. Give each a clear target and keyboard/accessibility semantics. Native tap conflict remains a runtime check. |
| D07 | Preserve | [AppState+Actions.swift](../../../apps/homelab-core/Sources/HomelabCore/App/AppState+Actions.swift) sends actions directly after iOS device authentication. | Keep Run or Merge → Face ID → submit. Show the target and consequence inline. Do not add a review screen. Keep Mac actions direct. |
| D08 | P1 | [MenuView.swift:102](../../../apps/homelab-menubar/Sources/HomelabMenuBarCore/Menu/MenuView.swift#L102) renders every pull request in a fixed-width menu without a bounded list area. | Bound the list height. Keep the header and footer outside the scroll region. Include View all on GitHub. |
| D09 | P1 | Health service rows identify individual service state through dot color. The collapsed sparkline chooses a metric without naming it. Duration bars omit status descriptions. | Add Up/Down text. Name the sparkline metric. Provide chart descriptions and text summaries. Preserve units and scales. |
| D10 | P2 | [Components.swift:115](../../../apps/homelab-ios/Sources/HomelabApp/Components.swift#L115) repeats a pulse without reading the motion preference. Health and log details use fixed timing. | Respect Reduce Motion. Use native transitions or a restrained custom spring. Keep status text when motion stops. |
| D11 | P1 | [HealthWidget.swift](../../../apps/homelab-ios/Sources/HomelabWidget/HealthWidget.swift) treats zero down services as healthy. Medium can show 0/0 and all up. Status and PR widgets also need explicit unknown states. | Distinguish unknown, empty, current, and cached. Add visible data age where space permits. Do not show a success symbol for no reading. |
| D12 | P2 | The widget source has no `widgetURL` or Link. The app root has no route handler. [PullRequestEntry](../../../apps/homelab-ios/Sources/HomelabWidget/PullRequestsWidget.swift) lacks a last-read timestamp. | Add route handling and a per-widget destination. Carry last-read time. Treat this as implementation work, not an existing capability. |
| D13 | P2 | The Mac device-code view has selectable text but no Copy control or authorization notice. Both platforms need explicit expiry recovery. | Give Copy, Open GitHub, Cancel, authorization notices, and New code consistent roles. Preserve the native browser handoff. |
| D14 | P2 | The Logs Live button retains the same word when inactive. The view does not expose the 500-line cap. Search is local to the fetched set. | Say Live or Paused. Explain scope. Preserve the read position and provide a New lines action if incoming rows need a buffer. |
| D15 | P2 | [ProfileView.swift](../../../apps/homelab-ios/Sources/HomelabApp/ProfileView.swift) says trigger, cancel, and merge all deploy. Mac Settings does not show the viewer identity and signs out immediately. | Explain each action accurately. Show the viewer and target. Use a deliberate sign-out control on both platforms. |
| D16 | P2 proposal | The current iOS and Mac pull request rows open GitHub. `pullRequestQuery` does not request the body. | Open an internal description view. Keep full body text, readiness, and the merge action. Exclude file changes. |

### Measured text contrast

Ratios use the sRGB values in the current palette and the standard relative-luminance formula.
They measure token pairs, not pixels from a device screenshot.

| Text and background | Current ratio | Normal-text target | Result |
|---|---:|---:|---|
| Dark tertiary `#5E6167` on surface `#121315` | 2.99:1 | 4.5:1 | Fails |
| Light tertiary `#9198A1` on surface `#FFFFFF` | 2.91:1 | 4.5:1 | Fails |
| Dark secondary `#8A8F98` on raised `#1A1B1E` | 5.30:1 | 4.5:1 | Passes |
| Light secondary `#6B7076` on raised `#F1F2F4` | 4.46:1 | 4.5:1 | Fails narrowly |

The revised HTML uses stronger text contrast and a blue action accent within the existing semantic roles.
The user selects compact rows and charts with minimal containers. Update the shared tokens when implementing this direction.

## Health correction and selected visual direction

The first HTML proposal drops information that exists in the native source.
It shows two hosts, two service rows, no summary strip, and only part of the host history.
It replaces the availability chart with a text disclosure. That is a coverage failure.

The corrected proposal restores the full information structure. It uses six hosts and 27 sample services.
Those values are fixtures, not current production observations.
The user selects a flat dashboard: compact rows, charts, and minimal containers.
The user also requests an iOS 26 Liquid Glass tab bar and appropriate glass controls.

| Native Health information | Corrected HTML coverage |
|---|---|
| Range and last refresh | Four ranges, independent of the Logs range; last-read and cached states |
| Service summary | Up/total and availability percentage |
| Host summary | Host count, reporting count, and strained count |
| Peak summary | Highest fractional peak, metric name, and host |
| Availability | Visible step chart with time labels, latest count, and peak count |
| Collapsed hosts | All six hosts; CPU, memory, root disk, load, and a named sparkline |
| Expanded hosts | Four charts per host; latest value, peak, time labels, percent scale, and separate load scale |
| Services | All 27 sample endpoints in six Host Label groups, with Up or Down text |
| Missing data | Neutral missing readings, retained service state, and explicit reporting count |
| Navigation | Floating glass tab bar, glass account/back controls, and clear scroll space at the end |

The CSS approximates the material. Native implementation uses the system APIs.
[Apple materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials) separates the glass navigation layer from content.
The [SwiftUI session](https://developer.apple.com/videos/play/wwdc2025/323/) describes the floating system tab bar.
The current app forces an opaque tab-bar background in RootView.swift. That override needs review during implementation.

## Pull request body proposal

Selecting a pull request opens its title, author, branch, readiness, and full body.
The iOS app uses a detail screen. The Mac app opens a separate reader window.
The proposal excludes file changes. The list position remains intact when the user returns.

The [current query](../../../apps/homelab-core/Sources/HomelabCore/GitHub/GitHubClient.swift) does not request a pull request body.
The implementation needs an on-demand body read for the selected repository and pull request number.
Keep large bodies out of the widget snapshot. Keep the body read separate from list readiness.
Render Markdown with readable headings, lists, links, code, and tables.
Add empty-body, loading, failed, cached, and conflict states. The merge action must retain the selected pull request number.

## Complete screen inventory

The HTML has 17 selectable screen families, including two pull request detail proposals.
Run and Merge stay on the current screen. The HTML simulates successful Face ID on iOS and shows an accepted request.
The HTML does not invoke Face ID or send a write.
The native app also has transient restore states and system-owned surfaces, listed below.

| Platform and surface | Current structure and behavior | Audit result and proposed coverage |
|---|---|---|
| iOS restore | RootView switches between checking, signed out, device code, and signed in. A spinner fills the screen. | Keep the route switch. Use a named load state. Native restore remains untested. HTML Loading previews cover the proposed status treatment. |
| iOS Sign in | One GitHub button, optional message, configuration disable state. | D01–D03, D13. HTML: Ready, Error, Not configured. |
| iOS Device code | Copyable code, browser link, notice, cancel. | Preserve existing copy and notice behavior. Improve step order and expiry recovery. HTML: Waiting, Network notice, Expired. |
| iOS Home | Workflow headline, metric strip, three workflow cards, charts, recent activity, external links, Account sheet. | D01–D07. HTML: Attention, Passed, Running, Awaiting approval, Loading, Stale, Error, No data. Keep every content section. |
| iOS workflow control | Start/cancel sends through AppState, with iOS device authentication where available. | D06–D07. Run and Cancel request device authentication, then submit. The mockup shows an accepted request inline. |
| iOS Pull requests | Ready and Waiting groups; draft, conflict, checking, mergeable, busy; external link and merge button. | Preserve groups and readiness vocabulary. D01–D07. HTML: Mixed, Empty, Loading, Stale, Error. |
| iOS Pull request detail | No current native view. | HTML: Description, No description, Loading, Stale, Error, Conflicts. Body content and the merge action use the selected PR. |
| iOS Health | Range, summary, availability chart, host cards, service groups, Account sheet. Off-tailnet can retain a cached reading. | D01–D05, D09. HTML: Attention, Healthy, Host no data, Loading, Stale, Unavailable, Error, No data. All summary fields, the availability chart, six hosts, and 27 sample services remain available. |
| iOS expanded host | One host expands to CPU, memory, disk, and load charts. | Keep the existing metrics and range. Use a semantic disclosure and name the collapsed metric. HTML includes six host disclosures, 24 readings, and 24 metric charts. All four readings remain visible when collapsed. |
| iOS Logs | Host and container menus, range, Live, level counts, local search, line list, clear filters, Account and log sheets. | D01–D05, D14. HTML: Paused, Live, Empty, Loading, Stale, Unavailable, Error. Filters and search operate on sample rows. |
| iOS Log detail | Parsed/inferred level, format, container filter action, full message, fields, stream labels, timestamps, raw disclosure, copy menu. | Preserve all evidence. D01–D03. HTML: Structured, Plain, copy, disclosure, container isolation, Done. |
| iOS Account | Viewer, profile link, repository, branch, read time, explanatory notes, Done. | Preserve the profile link and target. Correct action wording. HTML: Signed in, Viewer unavailable. |
| iOS sign-out dialog | Native confirmation dialog describes token removal and cached widgets. | Keep deliberate sign out. HTML uses an inline confirmation with the same consequence. Native dialog motion remains a device check. |
| iPad | Same screens; target family is 1 and 2. No separate iPad routes. | Use the same audit coverage. Constrain long text and adapt grids. HTML includes a 768-point width request; actual width depends on the browser pane. |
| Mac menu bar glyph | Workflow glyph; signed-out fallback; failed state uses multicolor. | Preserve the glyph. Add a useful accessibility label for status and age. Live native menu behavior remains untested. |
| Mac restore | Small spinner in a 320-point menu. | Keep it compact. Add a load description. HTML Menu → Loading. |
| Mac signed-out menu | Description, message, Sign in, Quit. | D13. HTML: Ready, Error, Not configured. |
| Mac device code | Selectable code, browser button, waiting state, Cancel. | D13. HTML: Waiting, Network notice, Expired, Copy. |
| Mac signed-in menu | Workflow rows, PR rows, links, error, read age, Refresh, Settings, Quit. | D05–D08. HTML: Attention, Passed, Running, Loading, Stale, Error, Long list. Footer stays outside the bounded list. |
| Mac Pull request detail | No current native view. | HTML uses a wider reader window with the full description and Back to menu. The same six body states apply. |
| Mac Settings | General grouped form; Launch at login; approval/error hint; Open Login Items; token explanation; sign out. | Preserve native form and login-item recovery. D15. HTML: Signed in, Signed out, Approval required, Error. |
| Mac notification | FailureNotifier sends a system notification when enabled by the existing behavior. | Preserve it. Notification delivery and macOS permission UI are system checks. No new notification proposal. |
| Widgets | Three configurations and 14 supported family combinations. | D11–D12. HTML exposes each supported family through the Widget family control. |

### Widget family coverage

| Widget | Source-declared families | Proposed states |
|---|---|---|
| Workflows | Small, medium, large, circular, rectangular, inline | Attention, Passed, Running, Stale, No data |
| Service health | Small, medium, rectangular, inline | Attention, Healthy, Stale, No data |
| Pull requests | Small, medium, rectangular, inline | Mixed, Empty, Stale, No data |

Lock-screen variants need monochrome status words and useful age information.
WidgetKit controls their size, tint, redaction, and refresh. HTML cannot verify those behaviors.

## States and interactions that need native verification

- Check keyboard coverage, focus order, and labels in each Mac menu state.
- Check VoiceOver reading order, disclosure state, selected filters, and copy announcements.
- Check all iOS text sizes, narrow phones, landscape, iPad, and keyboard insets.
- Check real pull-to-refresh on all tabs, including empty and failed states.
- Check restore and return-from-background with current, cached, expired, and revoked sessions.
- Check authentication allowed, canceled, failed, and unavailable paths. The current policy can proceed when evaluation is unavailable.
- Exercise workflow triggers, cancellation, and merge only with an approved safe test target.
- Check action failure, accepted-but-not-started, and uncertain transport results.
- Check that live logs stop in the background and do not move the user's read position.
- Check every widget family on the Home Screen and Lock Screen, including tinted presentation.

## Implemented changes

- Shared semantic fonts, improved contrast, flat content rows, and native controls.
- An iOS pull request reader that fetches the selected body without requesting file changes.
- Direct iOS Run, Cancel, and Merge actions behind the existing device authentication.
- All Health summaries, history, host readings, charts, and grouped services.
- Log read-position hold, new-line action, query scope, and local errors.
- A bounded Mac pull request list, internal reader windows, account details, and sign-out control.
- Widget unknown states, last-read age, and tab routes.

The changes use the existing SwiftUI targets and shared core. No new backend service is required.

## Deliverables and validation

- [index.html](index.html): self-contained local mockup; no libraries, fonts, or network data dependencies.
- [DESIGN.md](../../../DESIGN.md): adopted shared rules, platform rules, and release checks.
- This audit: findings, source links, screen inventory, priorities, and evidence limits.
- [VALIDATION.md](VALIDATION.md): HTML checks and remaining native checks.

The implementation changes app source only. It does not change infrastructure, credentials, or production state.


The findings and screen inventory record the source before implementation.
