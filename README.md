# Xcode Project Manager

A skill for AI coding agents (Claude Code, Cursor, etc.) to safely add source files, resource files, and groups to Xcode projects without manually editing `.pbxproj`.

## The Problem

AI agents frequently break Xcode projects when adding new files. The `.pbxproj` file is a complex OpenStep plist format with UUIDs that must be cross-referenced across PBXBuildFile, PBXFileReference, PBXGroup, and PBXSourcesBuildPhase sections. One wrong UUID = broken project.

## The Solution

A Ruby script wrapping the `xcodeproj` gem — the same library CocoaPods uses internally — that provides a simple CLI:

```bash
ruby scripts/xcode_add_files.rb \
  --project MyApp.xcodeproj \
  --target MyApp \
  --group "Features/Login" \
  --files MyApp/Features/Login/LoginVC.swift
```

## Features

- **26+ file types** auto-detected and routed to correct build phase (Sources / Resources / Headers)
- **Group management** — creates intermediate groups automatically, reuses existing ones
- **Idempotent** — safe to re-run; detects already-registered files
- **Dry-run mode** — preview changes without modifying the project
- **Empty group creation** — `--create-group` for directory groups, `--logical` for navigator-only groups
- **Zero dependencies** beyond the `xcodeproj` gem (already installed wherever CocoaPods or Fastlane is used)

## Installation

Copy the `xcode-project-manager/` directory into your project's skills directory:

```
your-project/
└── .claude/
    └── skills/
        └── xcode-project-manager/
            ├── SKILL.md
            └── scripts/
                └── xcode_add_files.rb
```

Or for Claude Code, place it in `~/.claude/skills/` for global availability.

## Usage

See [SKILL.md](SKILL.md) for full documentation and all supported file types.

Quick examples:

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
