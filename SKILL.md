---
name: xcode-project-manager
description: >
  Safely add or remove source files, resource files, and groups in an Xcode
  project (.pbxproj) without manual editing. Use this skill whenever you are
  working on an iOS, macOS, watchOS, tvOS, or visionOS project and create any
  new .m, .swift, .h, .mm, .c, .cpp, .metal, .json, .plist, .png,
  .storyboard, .xib, .strings, .ttf, .xcdatamodeld, .mlmodel, or
  .intentdefinition file that needs to appear in the Xcode project navigator
  and be compiled or bundled, OR whenever you need to remove files or groups
  from the Xcode project. Trigger on any mention of: "add to Xcode", "add to
  project", "new file in Xcode", "create group in Xcode", "add to target",
  "register in pbxproj", "Xcode project file", "remove from Xcode", "delete
  from project", "clean up Xcode project", "unregister from pbxproj", or
  whenever you write or delete a file in an Xcode project directory.
---

# Xcode Project Manager

Safely add and remove files and groups in an Xcode project via the `xcodeproj`
Ruby gem — the same library CocoaPods and Fastlane use internally.

**NEVER manually edit `.pbxproj`.** UUID generation, cross-referencing between
PBXBuildFile / PBXFileReference / PBXGroup / PBXSourcesBuildPhase, and
OpenStep plist formatting are all handled by the bundled scripts.

## Workflow

### Adding files

1. **Create the source file(s)** on disk at the desired path.
2. **Run `xcode_add_files.rb`** (see Usage below) to register them in the Xcode project.
3. **Verify** with `--dry-run` first if unsure about group or target names.

The add script is idempotent — if files are already registered, re-running is a safe no-op.

### Removing files

1. **Run `xcode_remove_files.rb`** (see Removing Files below) to unregister them.
2. **Use `--delete-files`** to also delete the files from disk.
3. **Verify** with `--dry-run` first to preview what will be removed.

### Removing groups

1. **Run `xcode_remove_files.rb --group`** to remove an empty group.
2. **Use `--recursive`** to also remove descendant files from build phases.
3. **Use `--delete-group`** to also remove the directory from disk.

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

## Removing files and groups

All removal commands reference `scripts/xcode_remove_files.rb`. Run them from
the directory containing the `.xcodeproj`.

### Remove files from project (keep files on disk)

```bash
ruby <skill-dir>/scripts/xcode_remove_files.rb \
  --project MyApp.xcodeproj \
  --target MyApp \
  --files MyApp/Features/Login/LoginVC.m MyApp/Features/Login/LoginVC.h
```

Removes the file references and build phase entries but **keeps the files on
disk**.

### Remove files from project AND delete from disk

```bash
ruby <skill-dir>/scripts/xcode_remove_files.rb \
  --project MyApp.xcodeproj \
  --target MyApp \
  --files MyApp/Old/Deprecated.swift --delete-files
```

### Remove an empty group from project only

```bash
ruby <skill-dir>/scripts/xcode_remove_files.rb \
  --project MyApp.xcodeproj \
  --target MyApp \
  --group "Features/OldModule"
```

Aborts if the group still contains file references or nested subgroups.
Use `--recursive` to remove contents as well.

### Remove a group and all its contents (recursive)

```bash
ruby <skill-dir>/scripts/xcode_remove_files.rb \
  --project MyApp.xcodeproj \
  --target MyApp \
  --group "Features/OldModule" --recursive
```

Removes all descendant file references from build phases, cleans up nested
subgroups, then removes the group itself.

### Remove a group AND delete the directory from disk

```bash
ruby <skill-dir>/scripts/xcode_remove_files.rb \
  --project MyApp.xcodeproj \
  --target MyApp \
  --group "Features/OldModule" --delete-group
```

### Removal options

| Flag | Effect |
|---|---|
| `--files a,b,c` | File paths to remove from project |
| `--delete-files` | Also delete removed files from disk |
| `--group PATH` | Group path to remove |
| `--recursive` | With `--group`: also remove all descendant files and nested subgroups |
| `--delete-group` | With `--group`: also delete the directory from disk |
| `--dry-run` | Preview changes without modifying the project |

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
