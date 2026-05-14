---
name: xcode-project-manager
description: >
  Safely add source files, resource files, and groups to an Xcode project
  (.pbxproj) without manual editing. Use this skill whenever you are working
  on an iOS, macOS, watchOS, tvOS, or visionOS project and create any new
  .m, .swift, .h, .mm, .c, .cpp, .metal, .json, .plist, .png, .storyboard,
  .xib, .strings, .ttf, .xcdatamodeld, .mlmodel, or .intentdefinition file
  that needs to appear in the Xcode project navigator and be compiled or
  bundled. Also trigger when you need to create new groups or folders in the
  Xcode project navigator. Trigger on any mention of: "add to Xcode",
  "add to project", "new file in Xcode", "create group in Xcode",
  "add to target", "register in pbxproj", "Xcode project file", or whenever
  you write a new file in an Xcode project directory that isn't yet part of
  the build.
---

# Xcode Project Manager

Safely add files and groups to an Xcode project via the `xcodeproj` Ruby gem —
the same library CocoaPods and Fastlane use internally.

**NEVER manually edit `.pbxproj`.** UUID generation, cross-referencing between
PBXBuildFile / PBXFileReference / PBXGroup / PBXSourcesBuildPhase, and
OpenStep plist formatting are all handled by the bundled script.

## Workflow

When this skill triggers:

1. **Create the source file(s)** on disk at the desired path.
2. **Run the script** (see Usage below) to register them in the Xcode project.
3. **Verify** with `--dry-run` first if unsure about group or target names.

The script is idempotent — if files are already registered, re-running is a
safe no-op.

## Prerequisites

The `xcodeproj` gem must be available. It is **automatically installed** as a
dependency of CocoaPods and Fastlane — if either is in the project, the gem
is already present. Verify with:

```bash
ruby -r xcodeproj -e 'puts Xcodeproj::VERSION'
```

If missing (SPM-only project, no CocoaPods):
```bash
gem install xcodeproj
```

## Usage

All commands reference `scripts/xcode_add_files.rb` relative to this skill's
directory. Run them from the directory containing the `.xcodeproj`:

### Add source/resource files

```bash
ruby <skill-dir>/scripts/xcode_add_files.rb \
  --project MyApp.xcodeproj \
  --target MyApp \
  --group "Features/Login" \
  --files MyApp/Features/Login/LoginVC.m MyApp/Features/Login/LoginVC.h
```

The script:
- Auto-detects file type from extension and routes to the correct build phase
- Creates intermediate groups if they don't exist
- Reuses existing groups when they do
- Is **idempotent** — re-running with the same files is safe
- Supports `--dry-run` to preview changes

### Create an empty group (mapped to a real directory)

```bash
ruby <skill-dir>/scripts/xcode_add_files.rb \
  --project MyApp.xcodeproj \
  --target MyApp \
  --group "Features/Settings" \
  --create-group
```

Creates both the Xcode group and the corresponding filesystem directory.

### Create an empty logical group (no directory on disk)

```bash
ruby <skill-dir>/scripts/xcode_add_files.rb \
  --project MyApp.xcodeproj \
  --target MyApp \
  --group "Vendor" \
  --create-group --logical
```

Pure Xcode navigator grouping — no directory created on disk.

## How to determine arguments

### `--project`
Path to the `.xcodeproj`. From the project root, this is typically
`ProjectName.xcodeproj` or `ios/ProjectName.xcodeproj`.

### `--target`
The Xcode target name — the name that appears in the Xcode scheme selector.
If unsure, list targets:
```bash
ruby -r xcodeproj -e 'p = Xcodeproj::Project.open("MyApp.xcodeproj"); puts p.targets.map(&:name)'
```

### `--group`
The group path in the Xcode Project Navigator, relative to the source root
group (the top-level group named after the project). Use `/` as separator.
Examples: `"Features/Login"`, `"Models"`, `"Resources/Images"`.

If the group doesn't exist yet, the script creates it (and any intermediate
groups) automatically. Groups are created with `path` matching their name,
so they map to real directories.

### `--files`
One or more file paths, relative to the current working directory.
These files must already exist on disk before running the script.

### `--source-group` (optional)
If auto-detection fails, specify the source root group explicitly.
Auto-detection tries (in order):
1. Group whose `path` matches the target name
2. Group whose `path` matches the project name
3. The group with the most children

## Supported file types

| Extension | Build Phase | `lastKnownFileType` |
|---|---|---|
| `.swift` | Sources | `sourcecode.swift` |
| `.m` | Sources | `sourcecode.c.objc` |
| `.mm` | Sources | `sourcecode.cpp.objcpp` |
| `.c` | Sources | `sourcecode.c.c` |
| `.cpp`, `.cc`, `.cxx` | Sources | `sourcecode.cpp.cpp` |
| `.metal` | Sources | `sourcecode.metal` |
| `.mlmodel` | Sources | `file.mlmodel` |
| `.intentdefinition` | Sources | `file.intentdefinition` |
| `.h` | Headers | `sourcecode.c.h` |
| `.hpp` | Headers | `sourcecode.cpp.h` |
| `.pch` | Sources | `sourcecode.c.h` |
| `.plist` | Resources | `text.plist.xml` |
| `.json` | Resources | `text.json` |
| `.storyboard` | Resources | `file.storyboard` |
| `.xib` | Resources | `file.xib` |
| `.xcassets` | Resources | `folder.assetcatalog` |
| `.png`, `.jpg`, `.gif`, `.pdf` | Resources | `image.*` |
| `.ttf`, `.otf` | Resources | `file` |
| `.strings` | Resources | `text.plist.strings` |
| `.xcdatamodeld` | Resources | `wrapper.xcdatamodeld` |
| `.framework`, `.dylib`, `.tbd`, `.a` | (none) | manual linking |

## Idempotency

The script is safe to run multiple times with the same arguments. It checks
whether a file is already referenced (by `real_path`) and already included
in the target's build phase — if so, it skips that file.

## Error recovery

If something goes wrong, the project is not saved. Fix the issue and re-run.
If a partial save occurred, use `git checkout` to restore the `.pbxproj`.

## Important notes

- Run from the directory containing the `.xcodeproj`, or use absolute paths.
- The script resolves `--files` paths relative to the current working directory.
- For `.h` files: added to Headers build phase. In modern Xcode projects this
  is harmless — headers are resolved via search paths and bridging headers.
- The `xcodeproj` gem preserves existing `.pbxproj` formatting — it won't
  reformat or reorder unrelated entries.
