# Homelab app design

Status: adopted on 22 October 2026.

This document defines the design rules for the iOS app, its widgets, and the macOS menu bar app.
The [audit](docs/design-audit/native-apps/AUDIT.md) records source findings and implementation status.
The [HTML mockup](docs/design-audit/native-apps/index.html) records the visual proposal with sample data.

## Purpose

Help the user answer three questions:

1. What needs attention?
2. What changed?
3. What action can I take?

Show the current state before history. Show detail when the user asks for it.
Use a flat dashboard with compact rows, readable charts, and minimal containers.
Use Liquid Glass for floating navigation and toolbar controls on iOS 26.
Keep charts, metrics, logs, and descriptions on a plain content surface.

## Shared direction

Keep the four iOS tabs: Home, Pull requests, Health, and Logs.
Keep Account behind the account button. Keep the Mac app in the menu bar.
Keep the shared palette roles, SF Symbols, and the Status → Topic → Detail order.
Use neutral surfaces and a blue action accent in the existing palette roles.
Keep the existing metric units, host names, and severity thresholds.
The [Grafana guide](docs/grafana-dashboard-style.md) controls Grafana dashboards. This document controls native apps.
Do not copy Grafana panel geometry onto a phone.

Use semantic text styles, adaptive layouts, and native controls.
Keep the direct write flow and existing device authentication.
Preserve every existing data category and control during a visual change.
Map each source screen to its proposal before calling the screen complete.
Do not remove information to make the screen look simpler.
Do not introduce a second palette or a second set of shared components.
Update the existing components and their callers together.

## Navigation

- Give each iOS tab its own navigation stack.
- Preserve the selected tab, scroll position, and filters after a sheet closes.
- Push a pull request detail screen from the iOS list. Keep the Pull requests tab selected.
- Open a separate reader window for a pull request on Mac. Keep the menu compact.
- Use a sheet for Account and a log detail.
- Keep a visible Done or Cancel control in each sheet.
- Use native navigation, sheet motion, menus, pickers, lists, and forms where they fit.
- Give every external link a clear destination and an external-link symbol.
- Keep external links separate from write controls.
- Add widget links to the relevant tab when the app supports route handling.
- Route each widget to its related tab when the user opens it.

## Status and data age

Each data source has its own state: loading, current, stale, empty, unavailable, or failed.
Keep GitHub, Prometheus, and Loki independent. A failed health request must not block the GitHub screens.

- Show “Loading workflows” before the first successful workflow read.
- Show “Status unknown” when the app has no valid reading.
- Show “All workflows passed” only when the observed workflows support that statement.
- Show “No open pull requests” only after a successful pull request read.
- Show “No service reading” for zero observed services.
- Show the last successful read time beside stale content.
- Describe an unreachable endpoint as unreachable. Do not infer that Tailscale is disconnected.
- Offer Retry next to a failed request.
- Keep the last successful content during refresh.
- Distinguish “Action accepted” from “Workflow running” and “Deployment complete”.
- Never show sample data as real status outside previews or the mockup.

A full implementation needs request state for each resource.
The shared snapshot timestamp cannot prove that every resource loaded successfully.
Choose an age limit from the existing polling schedule before adding age-based stale labels.
A failed read is stale immediately when cached content remains.

## Typography and layout

| Role | iOS | macOS |
|---|---|---|
| Screen title | Native large or inline title | System headline |
| Primary row | Body or headline | System body |
| Secondary detail | Subheadline or footnote | System secondary text |
| Metric | Scaled title style, tabular digits | System metric with tabular digits |
| Code or raw log | Scaled monospaced body | Monospaced system body |

- Support every Dynamic Type size. Do not cap text size to protect a grid.
- Use scaled metrics for a custom dimension that depends on text size.
- Wrap important labels. Move secondary data to another row when space is short.
- Stack metric tiles and key/value pairs at accessibility text sizes.
- Keep the existing spacing tokens until a measured layout change requires an update.
- Use 16-point phone gutters as the starting value.
- Separate dashboard sections with spacing and thin dividers.
- Use compact rows in place of repeated bordered cards.
- Reserve rounded containers for controls, floating navigation, and system sheets.
- Give iPad content a readable width. Use two columns only when each column remains readable.
- Fit the layout at 320 and 375 points and in landscape.
- Respect safe areas and keyboard insets.
- Show scroll indicators where they help the user find more content.

## Color and surfaces

Keep the semantic roles in `HomelabCore/Design/Palette.swift`.
Use the accent for actions and selection. Use status colors only for status.
Keep content surfaces solid. Let the system manage Liquid Glass in navigation and toolbar controls.
Honor Reduce Transparency and Increase Contrast.

On iOS 26, use a floating Liquid Glass tab bar above the scrolling content.
Let content continue beneath the bar. Add enough scroll clearance to expose the final row above it.
Use the material for the account control and appropriate navigation or toolbar buttons.
Keep filters, host readings, service rows, charts, and log messages flat.
Do not put glass behind every content group.

Use the native TabView, navigation, and toolbar APIs in the app.
Remove opaque tab-bar and navigation-background overrides that prevent the native material from appearing.
Do not reproduce the HTML blur and shadow in SwiftUI.
The HTML is a visual approximation; the system supplies the native material and its interaction.
Keep native navigation on older supported systems. Gate any iOS 26-only API by availability.
Test Reduce Transparency, Increase Contrast, and Reduce Motion with the real system controls.

| Meaning | Presentation |
|---|---|
| Passed or up | Positive color, success symbol, and text |
| Failed or down | Negative color, warning symbol, and text |
| Queued or running | Progress color, progress symbol, and text |
| Awaiting approval or strained | Warning color, symbol, and text |
| Unknown, missing, or stale | Neutral text and an explicit label |

Essential normal text needs a contrast ratio of at least 4.5:1.
Large text and meaningful control outlines need at least 3:1.
Measure both themes against the actual background, including tinted surfaces.
Do not use the current tertiary text color for essential small text without a contrast fix.
The mockup proposes stronger secondary and tertiary text colors within the existing palette roles.

## Controls and feedback

- Give iOS controls a hit area of at least 44 × 44 points.
- Use macOS control sizes that fit pointer and keyboard use. Do not copy phone targets into the menu.
- Use Button, Link, DisclosureGroup, Picker, and Toggle for their native semantics.
- Do not attach a row tap gesture around another action button.
- Name each icon control. Include the workflow or pull request in its accessibility label.
- Expose selected, expanded, disabled, and busy states to accessibility tools.
- Provide immediate pressed feedback without changing the layout.
- Disable only the action in progress.
- Place a request failure beside the action that failed.
- Keep an action failure visible until dismissal or a successful retry.
- Announce copy confirmation to VoiceOver. Keep a visible copied state.

## Workflow and merge actions

On iOS, use this sequence: tap Run or Merge → Face ID → submit the action.
Keep the existing device authentication policy and its passcode fallback.
Do not add a separate review screen or confirmation dialog for Run, Cancel, or Merge.
If the user cancels authentication, submit nothing.
Keep Mac actions direct. Do not add a Mac authentication requirement through this design change.

Show the target and consequence on the existing workflow card or pull request detail.
Use direct labels such as “Run Update”, “Cancel Update run”, and “Squash merge #128”.
Keep the selected pull request number attached to the merge action.
Say that the merge starts the deployment workflow. Do not describe cancellation as a deployment.
Do not imply that a biometric prompt exists when the device cannot evaluate the current authentication policy.

After submission, show an accepted state and a link to the run when available.
If the result is uncertain, refresh before offering another write.
Do not retry a write automatically.

## Screen rules

| Screen | Required behavior |
|---|---|
| Sign in | One primary action; explain a disabled configuration; keep the error and retry visible. |
| Device code | Selectable code, Copy button, Open GitHub button, Cancel, and the authorization notice. |
| Home | Workflow status first; visible run state; separate run link and write control; history below. |
| Pull requests | Ready and waiting groups; select a row to read its body; preserve the list position on return. |
| Pull request detail | Title, author, target branch, readiness, and full body; no file diff or file list. |
| Health | Range, read age, service count, availability percentage, host count, strained hosts, peak metric, availability chart, every host, and every service group. |
| Host detail | CPU, memory, root disk, and load stay visible when collapsed. Show a named sparkline. Expansion reveals all four charts with latest values, peaks, units, and time axes. |
| Logs | Host, container, and range remain visible; label search as local to the fetched lines. |
| Log stream | Distinguish Live from Paused; preserve the read position; disclose the 500-line limit. |
| Log detail | Full message, fields, stream labels, both timestamps, raw line, and copy actions remain available. |
| Account | Account, target repository, branch, read time, and sign out; explain actual authentication behavior. |
| Mac menu | Bounded list area; persistent header and footer; visible read time, Refresh, Settings, and Quit. |
| Mac Settings | Native grouped form; account identity; login-item state and recovery; deliberate sign out. |
| Widgets | Unknown state, data age, status words, and a route into the app; no write action. |

Render the full pull request body with headings, lists, code, links, and tables.
Keep the body selectable. Wrap long words and let wide tables scroll inside the body.
Show “No description provided” when the body is empty.
Keep the title visible while the body loads. Keep Retry beside a failed body request.
Keep the merge action tied to the selected pull request number.
Do not offer a merge for a conflicting pull request. Refresh stale readiness before a merge.
Keep Open on GitHub as a secondary action. Do not fetch or show file changes for this view.

Do not add Health or Logs to the Mac app through a design-only change.
A long Mac pull request list needs a bounded scroll region or a “View all on GitHub” link.
Keep the existing Mac notification behavior.

## Health information coverage

The Health screen retains all content from HealthView.swift and ChartViews.swift.

- Keep 1H, 6H, 24H, and 7D. Apply the selected range to every history chart.
- Keep the number of services up, total services, and availability percentage.
- Keep the total host count, reporting state, and strained-host count.
- Keep the peak fractional metric, its name, its value, and its host.
- Keep the failed-endpoint history visible as a step chart.
- Keep all hosts. Show CPU, memory, root disk, and load for each host before expansion.
- Let each host expand to all four charts. Keep the expanded host open when the range changes.
- Keep every service, grouped by Host Label, with Up or Down text.
- Keep cached, unavailable, failed, and missing-reading states distinct.

The HTML uses six hosts and 27 sample services to show complete screen coverage.
The counts and measurements are illustrative. They do not describe current production state.

## Charts and logs

- Preserve the existing fraction scale of 0–100 percent and the separate load scale.
- Preserve the step interpolation for the number of failed services.
- Label a collapsed sparkline with its metric. The current choice can change between hosts.
- Pair duration-bar colors with run status text and a readable history summary.
- Provide a text alternative or accessible chart description for each chart.
- Preserve the full log message and raw line in the detail sheet.
- Keep declared and inferred log levels distinct.
- Explain that search and level counts apply to the fetched lines, not all records in Loki.
- Do not move rows while the user reads older log lines.
- Add a “New lines” control if the implementation buffers incoming lines away from the current position.

## Motion

Use system transitions first. Preserve their interruption and gesture behavior.
Use a short, non-bouncing spring for a custom disclosure when motion adds clarity.
Respect Reduce Motion. Replace motion with a static state or a short crossfade.
Do not run a repeating pulse when Reduce Motion is enabled.
Do not add decorative motion to metrics, logs, or the Mac menu.

## Review before release

Check each changed screen with current, loading, empty, stale, unavailable, and failed data where applicable.
Check iPhone, iPad, both themes, all text sizes, VoiceOver, and Reduce Motion.
Check the Mac menu with a short display and a long pull request list.
Use Tab, Shift-Tab, Return, Space, and Escape to check Mac controls.
Check the launch, return-from-background, and pull-to-refresh paths on each iOS tab.
Check external links, sheet dismissal, action cancellation, and local action failures.
Check every supported widget family, including monochrome and tinted presentation.
Record native device checks separately from HTML checks and compile checks.

## Basis

- [Apple Design skill](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md): response, continuity, typography, and accessibility.
- [Apple materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials): Liquid Glass for the functional layer above content.
- [Apple SwiftUI design session](https://developer.apple.com/videos/play/wwdc2025/323/): native floating tab bars and navigation.
- [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill): interaction, accessibility, state clarity, and native controls.
- Existing source, [app README](apps/homelab-ios/README.md), and [token decision](docs/adr/0004-the-ios-app-holds-a-token.md).

The skills guide the review. Product needs and native platform behavior control the final design.
