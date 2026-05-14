# Xcode Project Manager

A skill for AI coding agents to safely add source files, resource files, and groups to Xcode projects without manually editing `.pbxproj`.

## The Problem

AI agents frequently break Xcode projects when adding new files. The `.pbxproj` file is a complex OpenStep plist with UUIDs cross-referenced across multiple sections. One wrong UUID = broken project.

## The Solution

A Ruby script wrapping the `xcodeproj` gem — the same library CocoaPods uses — that provides a simple CLI:

```bash
ruby scripts/xcode_add_files.rb \
  --project MyApp.xcodeproj \
  --target MyApp \
  --group "Features/Login" \
  --files MyApp/Features/Login/LoginVC.swift
```

## Features

- **26+ file types** auto-detected and routed to correct build phase
- **Group management** — creates intermediate groups, reuses existing ones
- **Idempotent** — safe to re-run
- **Dry-run mode** — preview without modifying the project
- **Empty group creation** — `--create-group` for directory groups, `--logical` for navigator-only groups

## Install

```bash
npx skills add CaffreySun/xcode-project-manager
```

Or for Claude Code:

```bash
claude plugins install github.com/CaffreySun/xcode-project-manager
```

## Usage

See [SKILL.md](SKILL.md) for full documentation and all supported file types.

```bash
# Add Swift + ObjC files
ruby scripts/xcode_add_files.rb \
  --project MyApp.xcodeproj --target MyApp \
  --group "Features/Auth" \
  --files MyApp/Features/Auth/LoginView.swift MyApp/Features/Auth/AuthManager.m

# Create empty directory group
ruby scripts/xcode_add_files.rb \
  --project MyApp.xcodeproj --target MyApp \
  --group "Features/Settings" --create-group

# Dry-run to preview
ruby scripts/xcode_add_files.rb \
  --project MyApp.xcodeproj --target MyApp \
  --group "Models" \
  --files MyApp/Models/User.swift --dry-run
```

## Requirements

- Ruby (macOS comes with it)
- `xcodeproj` gem (auto-installed with CocoaPods or Fastlane; otherwise `gem install xcodeproj`)

## License

MIT
