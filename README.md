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

## Features

- **Any extension works** — not just common ones. Type any extension (e.g. `abc`)
  and macOS resolves it to a UTI automatically; you can assign a default app to it.
- **Live current default** — for every extension see the current default app
  (icon, name, bundle ID), read straight from LaunchServices.
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
./build.sh          # builds DefaultApp.app + lsctl test CLI into .build/
open DefaultApp.app
```

Requirements: macOS 14+, Xcode Command Line Tools. No third-party dependencies;
the app is ad-hoc signed.

## How it works

- Extension → UTI: `UTType(tag: .filenameExtension)` (works for unknown
  extensions via dynamic UTIs).
- Current handler: `LSCopyDefaultRoleHandlerForContentType` (viewer → editor → any).
- Candidate apps: `LSCopyAllRoleHandlersForContentType` (editor + viewer roles).
- Set default: `LSSetDefaultRoleHandlerForContentType`.
- User-vs-system detection: parses `LSHandlers` in
  `~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist`
  (plus changes made by this app itself).

Changes take effect immediately — verified end-to-end by opening real files.

## Test CLI

`build.sh` also builds `.build/lsctl`, a CLI over the same LaunchServices bridge:

```bash
.build/lsctl get txt                     # current default for .txt
.build/lsctl list png                    # all apps that can open .png
.build/lsctl set txt com.sublimetext.4 all
```

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
Sources/TestCLI/             lsctl test CLI
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
