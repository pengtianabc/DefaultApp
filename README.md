# DefaultApp · 默认打开方式

A lightweight macOS app to view and change the default application for **any** file
extension — the equivalent of Windows Explorer's "Open with → Always use this app",
built directly on LaunchServices.

Language / 语言: **English** | [简体中文](README.zh-CN.md)

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/swift-SwiftUI%20%2B%20LaunchServices-orange)
![License](https://img.shields.io/badge/license-MIT-green)

<p align="center">
  <img src="Screenshots/icon.png" width="128" height="128" alt="DefaultApp icon" />
</p>
<p align="center">
  <img src="Screenshots/main.png" width="760" alt="DefaultApp main window" />
</p>
<p align="center"><i>Main window (Simplified Chinese UI; English & “Follow System” built in)</i></p>

## Install & First Launch

Download from [Releases](https://github.com/pengtianabc/DefaultApp/releases) (or a
friend may send it to you) and drag `DefaultApp.app` into **Applications**.

> **Blocked by “cannot be opened” on first launch?** That is macOS Gatekeeper,
> not a problem with your Mac — the app is ad-hoc signed and not notarized yet.
> Just once: **Control-click (or right-click) the app → Open → Open again**,
> or allow it in **System Settings → Privacy & Security**. It runs normally
> after that.

## Features

- **URL scheme management** — beyond file extensions: default browser (`https`),
  default mail client (`mailto`), `ftp`/`ssh`/`tel` and more, in a dedicated
  Schemes tab. Changes are effective immediately, same as extensions.
- **Any extension works** — not just common ones. Type any extension (e.g. `abc`)
  and macOS resolves it to a UTI automatically; you can assign a default app to it.
- **Live current default** — for every extension see the current default app
  (icon, name, bundle ID), resolved **the same way macOS resolves a
  double-click** (`NSWorkspace`), not just the role-registration API; warns
  when the two disagree.
- **Set with verification** — after writing, the change is read back through
  the double-click resolution path to confirm it actually took effect.
- **Apps view** — inspect app ↔ extension relations per app: which extensions
  it owns as default, which it can open, and its declared document types.
- **User vs. System marker** — each extension's handler is tagged
  **CUSTOM** (explicitly set by the user, stored in the LaunchServices user
  preference database) or **SYSTEM** (inferred from app declarations), so you
  always know whether a setting is yours or shipped/defaulted.
- **All candidate apps** — pick a new default from every app that declared it can
  open the type, or choose any `.app` from disk via a file panel.
- **Roles** — register as Viewer, Editor, or All (`LSSetDefaultRoleHandlerForContentType`).
- **Categorized quick-add** — batch-add common extensions by category
  (Documents / Code / Images / Video / Audio / Email / Archives / Other) with
  category single-select + extension multi-select.
- **Search & filter** — keyword search by extension or app name; filter by
  All / Custom / System.
- **Starter list** — first launch pre-populates common extensions across
  categories (Documents / Code / Images / Video / Audio / Email / Archives), so
  you immediately see real default apps; the list is yours to edit afterward.
- **In-app language switch** — 简体中文 / English / Follow System, switchable
  live from the toolbar.
- Your extension list is persisted between launches.

## Build & Run

```bash
./build.sh          # builds DefaultApp.app + defaultapp CLI into .build/
open DefaultApp.app
```

Requirements: macOS 14+, Xcode Command Line Tools. No third-party dependencies;
the app is ad-hoc signed.

## How it works

- Extension → UTI: `UTType(tag: .filenameExtension)` (works for unknown
  extensions via dynamic UTIs).
- Current handler: `LSCopyDefaultRoleHandlerForContentType` (viewer → editor → any).
- Candidate apps: `LSCopyAllRoleHandlersForContentType` (editor + viewer roles).
- Set default: `LSSetDefaultRoleHandlerForContentType`. With the **All** role it
  stamps all three slots — **viewer / editor / all** — so Finder double-click,
  the `open` command, and in-app requests all resolve to the same app. This also
  overwrites apps that squatted on the "all roles" slot only (e.g. WorkBuddy
  taking over `.md`).
- User-vs-system detection: parses `LSHandlers` in
  `~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist`
  (plus changes made by this app itself).

Changes take effect immediately — verified end-to-end by opening real files
with `open` after each change.

## FAQ

**Q: How long until a change takes effect?**
Immediately. Once written to LaunchServices, Finder double-click and the
`open` command use the new default right away — no restart needed.

**Q: Setting failed with “LaunchServices rejected the change”?**
That API refuses apps that do not declare the file type in their Info.plist
(Edge, for example, does not declare `public.html`). The tool falls back to
the macOS 12+ NSWorkspace API (the same one System Settings uses) and finally
stamps the viewer/editor/all slots directly — verified working with
undeclared apps (html → Edge).

**Q: Why did `.md` files keep opening in WorkBuddy?**
LaunchServices stores default handlers per role (viewer / editor / all). Some
apps (e.g. WorkBuddy) squat on the "all roles" slot only, which made the system
resolve differently than expected. Setting the default with the **All** role in
this app overwrites all three slots at once; the detail pane also shows who
holds the "all roles" slot if it ever disagrees.

## CLI: `defaultapp`

Beyond the GUI, the project ships a fully functional command-line tool named
`defaultapp`, sharing the same LaunchServices bridge as the app — anything the
app can do also works in a terminal, handy for remote machines and scripting.
`./build.sh` compiles it to `.build/cli/defaultapp`, and releases also publish a
ready-to-use binary.

```bash
./build.sh   # builds the app and defaultapp

# optional: put it on your PATH
install -m 755 .build/cli/defaultapp /usr/local/bin/defaultapp
```

```bash
defaultapp get md                      # what opens .md: double-click resolution,
                                       # role registration and the all-roles slot
                                       # side by side; ⚠ MISMATCH + fix hint when
                                       # they disagree
defaultapp list png                    # every app that declared it can open .png
                                       # (app name first, dim bundle id after; *
                                       # marks the current default)
defaultapp set txt "Sublime Text"      # set default by app name, bundle id, or path
                                       # (/Applications/Sublime Text.app — paths
                                       # inside the bundle work too) — stamps all
                                       # three role slots, effective immediately
defaultapp set txt com.sublimetext.4 viewer   # or a single role: viewer|editor|all
defaultapp unset txt                   # remove your override; hand it back to macOS
defaultapp check                       # scan all common extensions and list the
                                       # ones where the registered role differs
                                       # from the actual double-click open target
defaultapp scheme                      # URL schemes: scheme [get|list|set|unset] <scheme> [app]
defaultapp scheme https                # current handler for https (default browser)
defaultapp scheme set mailto Mail      # set a scheme handler (name/bundle-id/path)
defaultapp scheme unset https          # restore the system default
defaultapp apps                        # the Apps tab as a CLI: every app linked to
                                       # the common extensions, sorted by default count
defaultapp apps Cursor                 # one app: extensions it is default for, can
                                       # open, and its declared document types (UTI
                                       # and legacy CFBundleTypeExtensions forms)
defaultapp get md --json               # get / list / check support --json output
defaultapp version                     # print version
defaultapp help                        # full help
```

Output is TTY-aware: aligned columns with colors on a terminal, plain text when
piped or redirected, and `NO_COLOR=1` forces colors off.

> **CLI downloaded from Releases blocked on first run?** Binaries downloaded via
> a browser carry the quarantine xattr, so the shell may report
> `cannot be opened` / `killed`. Run
> `xattr -d com.apple.quarantine defaultapp` once (use the path you installed
> it to, e.g. `/usr/local/bin/defaultapp`). Binaries built from a `git clone`
> are unaffected.

## Project layout

```
Sources/App/                 app sources (SwiftUI)
  MainApp.swift              entry point
  I18n.swift                 in-app localization (zh-CN / en)
  ExtensionCatalog.swift     categorized common-extension catalog
  ContentView.swift          sidebar: search, filter, quick-add panel, list
  DetailView.swift           per-extension detail & set-default actions
  AppState.swift             model, persistence, user/system source detection
  LaunchServicesBridge.swift LaunchServices wrappers + UserOverrides parser
Sources/IconGen/             app-icon generator (compiled & run by build.sh)
Sources/TestCLI/             defaultapp command-line tool
build.sh                     one-shot build (icon → app → CLI → .app bundle)
.github/workflows/           CI + release workflows
```

## Download

Prebuilt `DefaultApp.dmg` / `.zip` are attached to
[GitHub Releases](https://github.com/pengtianabc/DefaultApp/releases)
(via CI — see below).

## CI / Release

- Every push / PR: the app is built and smoke-tested on a macOS runner
  (`.github/workflows/ci.yml`).
- Pushing a `v*` tag creates a GitHub Release with a signed-ad-hoc `.app` in a
  DMG and a ZIP (`.github/workflows/release.yml`):

```bash
git tag v1.0.0 && git push origin v1.0.0
```

## License

MIT
