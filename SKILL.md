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
  whenever you create a new file or delete a file in an Xcode project directory.
---

# Xcode Project Manager

Safely add and remove files and groups in an Xcode project via the `xcodeproj`
Ruby gem — the same library CocoaPods and Fastlane use internally.

**NEVER manually edit `.pbxproj`.** UUID generation, cross-referencing between
PBXBuildFile / PBXFileReference / PBXGroup / PBXSourcesBuildPhase, and
OpenStep plist formatting are all handled by the bundled scripts.

## Quick reference

- **Add**: create files on disk, then run `<skill-dir>/scripts/xcode_add_files.rb` (see below)
- **Remove files**: run `<skill-dir>/scripts/xcode_remove_files.rb`; add `--delete-files` to also delete from disk
- **Remove group**: run `<skill-dir>/scripts/xcode_remove_files.rb --group G`; add `--recursive` for non-empty groups, `--delete-group` to delete directory
- Always preview with `--dry-run` first when unsure

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

## How to determine arguments

### `--project`
Path to the `.xcodeproj`. From the project root, this is typically
`ProjectName.xcodeproj` or `ios/ProjectName.xcodeproj`.

### `--target`
The Xcode target name — the name that appears in the Xcode scheme selector.
Required even for group-only operations — the script uses the target name
to locate the source root group within the project.
If unsure, list targets:
```bash
ruby -r xcodeproj -e 'p = Xcodeproj::Project.open("MyApp.xcodeproj"); puts p.targets.map(&:name)'
```

### `--group`
The group path in the Xcode Project Navigator, relative to the source root
group (the top-level group named after the project). Use `/` as separator.
Examples: `"Features/Login"`, `"Models"`, `"Resources/Images"`.

When **adding**, if the group doesn't exist yet, the script creates it (and
any intermediate groups) automatically, with a matching directory on disk.
When **removing**, the group must already exist in the project.

### `--files`
One or more file paths, relative to the current working directory.
Accepts both space-separated (`--files a.m b.h`) and comma-separated
(`--files a.m,b.h`) forms.
These files must already exist on disk before running the **add** script.

### `--source-group` (optional)
If auto-detection fails, specify the source root group explicitly.
Auto-detection tries (in order):
1. Group whose `path` matches the target name
2. Group whose `path` matches the project name
3. The group with the most children

## Usage

In all examples below, replace `<skill-dir>` with this skill's root directory
(the directory containing `SKILL.md` and `scripts/`).
Run commands from the directory containing the `.xcodeproj`:

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
- If auto-detection of the source root group fails, use `--source-group` (see above)

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

Use `<skill-dir>/scripts/xcode_remove_files.rb` for all commands below.
Run from the directory containing the `.xcodeproj`.

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
Unlike `--group` in add mode, the group **must already exist** in the project.
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
| --- | --- |
| `--files FILE [FILE...]` | File paths to remove from project (space or comma-separated) |
| `--delete-files` | Also delete removed files from disk |
| `--group PATH` | Group path to remove |
| `--recursive` | With `--group`: also remove all descendant files and nested subgroups |
| `--delete-group` | With `--group`: also delete the directory from disk |
| `--dry-run` | Preview changes without modifying the project |

## Supported file types

| Extension | Build Phase | `lastKnownFileType` |
| --- | --- | --- |
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

## Troubleshooting

### "Target 'X' not found"
The script prints all available target names. Verify `--target` against that
list. Common mistake: using the project name when the target name differs
(check the Xcode scheme selector). `--target` is required even for group-only
operations — the script uses it to locate the source root group.

### "Group not found: X" (remove mode)
The group must already exist in the project. Use `--source-group` if the
group is under a non-standard root. Check the path separator is `/` and the
path is relative to the source root group.

### Source root group auto-detection fails
Use `--source-group` to specify the root group explicitly (see above).
This happens when the project structure doesn't match the common patterns
(e.g. target name ≠ group name, deeply nested workspaces).

### Command fails with "cannot load such file" or no output
The `xcodeproj` gem is not installed. Run `gem install xcodeproj` (see
Prerequisites). Also verify you're running from the directory containing
the `.xcodeproj`. Use `--dry-run` to test arguments safely.

## Idempotency

Both scripts are safe to run multiple times with the same arguments:
- **Add**: skips files already referenced (checked by `real_path`) and already
  included in the target's build phase.
- **Remove**: skips files or groups not found in the project — produces a
  warning but does not error.

## Safety & notes

- **No partial saves**: if something goes wrong, the project is not saved.
  Fix the issue and re-run. If recovery is needed, `git checkout` the `.pbxproj`.
- Run from the directory containing the `.xcodeproj`, or use absolute paths.
- The script resolves `--files` paths relative to the current working directory.
- For `.h` files: added to Headers build phase. In modern Xcode projects this
  is harmless — headers are resolved via search paths and bridging headers.
- The `xcodeproj` gem preserves existing `.pbxproj` formatting — it won't
  reformat or reorder unrelated entries.
