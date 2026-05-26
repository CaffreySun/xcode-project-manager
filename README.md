# Xcode Project Manager

A skill for AI coding agents to safely add and remove source files, resource files, and groups in Xcode projects without manually editing `.pbxproj`.
## Install

```bash
npx skills add CaffreySun/xcode-project-manager
```

Or for Claude Code:

```bash
claude plugins install github.com/CaffreySun/xcode-project-manager
```

## The Problem

AI agents frequently break Xcode projects when adding new files. The `.pbxproj` file is a complex OpenStep plist with UUIDs cross-referenced across multiple sections. One wrong UUID = broken project.

## The Solution

A Ruby script wrapping the `xcodeproj` gem — the same library CocoaPods uses — that provides a simple CLI for AI agents to register files safely.

## Features

- **26+ file types** auto-detected and routed to correct build phase
- **Group management** — creates intermediate groups, reuses existing ones
- **Idempotent** — safe to re-run add/remove operations
- **Dry-run mode** — preview without modifying the project
- **Empty group creation** — `--create-group` for directory groups, `--logical` for navigator-only groups
- **File removal** — unregister files from project, optionally delete from disk
- **Group removal** — remove groups with optional recursive cleanup and disk deletion

## License

MIT
