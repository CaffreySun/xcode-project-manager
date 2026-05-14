# Xcode Project Manager

A skill for AI coding agents to safely add source files, resource files, and groups to Xcode projects without manually editing `.pbxproj`.

## The Problem

AI agents frequently break Xcode projects when adding new files. The `.pbxproj` file is a complex OpenStep plist with UUIDs cross-referenced across multiple sections. One wrong UUID = broken project.

## The Solution

A Ruby script wrapping the `xcodeproj` gem — the same library CocoaPods uses — that provides a simple CLI for AI agents to register files safely.

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

## Requirements

- Ruby (macOS comes with it)
- `xcodeproj` gem (auto-installed with CocoaPods or Fastlane; otherwise `gem install xcodeproj`)

## License

MIT
