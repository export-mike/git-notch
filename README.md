# S8 Notch

An elegant macOS agent app that lives around the MacBook notch and surfaces the
GitHub pull requests that actually need you — nothing else. No dock icon, no
menu-bar clutter.

- **Left of the notch** — a GitHub mark with a red ring + count for PRs
  **awaiting your review** (`is:open is:pr review-requested:@me archived:false draft:false`).
- **Right of the notch** — PRs **you authored that need attention**: reviewers
  requested changes, any formal review landed, required CI is failing, or there
  are unresolved review comments.

Click either side to drop down a list — repo, title, a one-line summary of
what's going on, and how long ago it moved. Click a row to open it in your
browser.

## How it works

- **Auth**: reuses your existing GitHub CLI session — it reads the token from
  `gh auth token` at launch. Nothing to configure; just be logged in
  (`gh auth login`).
- **Data**: a single GitHub GraphQL query per refresh pulls both lists plus each
  of your PRs' review decision, CI rollup, and review threads.
- **UI**: a borderless, non-activating `NSPanel` at status-bar level, positioned
  from `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea` so it hugs the notch on
  any Mac (and falls back to a top-centre pill on notch-less displays).

## Build & run

```sh
./build.sh            # compiles release + assembles S8Notch.app
open S8Notch.app      # launch (or run the binary directly to see logs)
```

Requires the Swift toolchain (Xcode CLT), macOS 14+, and `gh` installed &
authenticated.

## Settings

Open via the gear in any dropdown. Tune which signals light the right badge
(changes-requested / any review feedback / failing CI / unresolved comments),
set an optional `commenter` filter, choose the refresh interval, and toggle
launch-at-login.

## Layout

```
Sources/S8Notch/
  main.swift              app entry (accessory / LSUIElement)
  AppDelegate.swift       boots the controller, watches screen changes
  AppState.swift          observable model: fetch + classify
  Settings.swift          persisted config (UserDefaults)
  GitHub/
    GitHubClient.swift    gh token + GraphQL fetch
    Models.swift          PullRequest domain model + attention signals
  Notch/
    NotchGeometry.swift   notch position/size math
    NotchController.swift windows, refresh timer, click handling
  Views/
    Icons.swift           embedded GitHub mark (SVG template image)
    NotchBarView.swift     the two clusters flanking the notch
    DropdownView.swift    the PR list + footer
    SettingsView.swift    settings form
```
