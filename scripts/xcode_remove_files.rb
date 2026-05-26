#!/usr/bin/env ruby
# frozen_string_literal: true

# xcode_remove_files.rb — Safely remove source/resource files and groups from
# an Xcode project (.pbxproj).
#
# Uses the xcodeproj gem (available wherever CocoaPods or Fastlane is
# installed) to manipulate the .pbxproj.  UUID generation, cross-referencing,
# and format preservation are all handled — this is the same library
# CocoaPods itself uses internally.
#
# === Remove files from project only (keep files on disk) ===
#   ruby xcode_remove_files.rb \
#     --project MyApp.xcodeproj \
#     --target MyApp \
#     --files MyApp/Features/Login/LoginVC.m MyApp/Features/Login/LoginVC.h
#
# === Remove files from project AND delete from disk ===
#   ruby xcode_remove_files.rb \
#     --project MyApp.xcodeproj \
#     --target MyApp \
#     --files MyApp/Features/Login/LoginVC.m --delete-files
#
# === Remove an empty group from project only ===
#   ruby xcode_remove_files.rb \
#     --project MyApp.xcodeproj \
#     --target MyApp \
#     --group "Features/Login"
#
# === Remove a group and its contents from project (recursive) ===
#   ruby xcode_remove_files.rb \
#     --project MyApp.xcodeproj \
#     --target MyApp \
#     --group "Features/Login" --recursive
#
# === Remove a group AND delete the directory from disk ===
#   ruby xcode_remove_files.rb \
#     --project MyApp.xcodeproj \
#     --target MyApp \
#     --group "Features/Login" --delete-group
#
# All operations support --dry-run to preview.

require "xcodeproj"
require "optparse"
require "fileutils"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def log(msg)
  $stderr.puts "  #{msg}"
end

def warn(msg)
  $stderr.puts "WARNING: #{msg}"
end

# Resolve a group path relative to `base_group`.
# Returns the matching group, or nil if not found.
def find_group_at_path(base_group, components)
  current = base_group
  components.each do |segment|
    found = current.children.find { |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) &&
        (c.path == segment || c.name == segment)
    }
    return nil unless found
    current = found
  end
  current
end

# Build a list of all file references that are descendants of `group`.
def descendant_file_refs(group)
  file_refs = []
  group.recursive_children.each do |c|
    file_refs << c if c.is_a?(Xcodeproj::Project::Object::PBXFileReference)
  end
  file_refs
end

# Remove a single PBXBuildFile from all build phases it appears in within
# the given target. The xcodeproj gem's ObjectList#delete handles removal
# from the project objects when no referrers remain.
def purge_build_file(target, build_file)
  removed_from = []
  [target.source_build_phase,
   target.resources_build_phase,
   target.headers_build_phase,
   target.frameworks_build_phase].compact.each do |phase|
    phase.files.to_a.each do |existing|
      next unless existing.uuid == build_file.uuid
      phase.files.delete(existing)
      removed_from << phase.class.name.split("::").last
    end
  end
  removed_from
end

# Remove a single file reference from the project: purge associated build
# files from all target build phases, remove the file ref from its parent
# group. The xcodeproj gem's ObjectList#delete handles removal from the
# project objects when no referrers remain.
def remove_file_ref(project, target, file_ref, delete_from_disk: false)
  # Capture real_path before removal — parent chain is lost after
  # removing from the group.
  real = file_ref.real_path.to_s
  file_basename = File.basename(real)

  # Purge PBXBuildFile entries that reference this file_ref
  build_files = project.objects.select { |o|
    o.is_a?(Xcodeproj::Project::Object::PBXBuildFile) && o.file_ref == file_ref
  }

  build_files.each do |bf|
    phases = purge_build_file(target, bf)
    phases.each { |p| log "Removed from #{p}: #{file_basename}" }
  end

  # Remove from parent group
  parent_group = find_parent_group(project, file_ref)
  if parent_group
    parent_group.children.delete(file_ref)
    group_label = parent_group.path || parent_group.name || "root"
    log "Removed from group '#{group_label}': #{file_basename}"
  end

  log "Removed file ref: #{file_basename}"

  # Optionally delete from disk
  if delete_from_disk
    if File.exist?(real)
      FileUtils.rm_rf(real)
      log "Deleted file: #{real}"
    else
      warn "File not found on disk: #{real}"
    end
  end
end

# Find the PBXGroup that directly contains `child`.
def find_parent_group(project, child)
  project.main_group.recursive_children.each do |c|
    next unless c.is_a?(Xcodeproj::Project::Object::PBXGroup)
    return c if c.children.any? { |ch| ch.uuid == child.uuid }
  end
  nil
end

# Locate the source root group — the group under main_group that contains
# the project's actual source tree.
#  1. path == target_name
#  2. path == project_name
#  3. Largest group by children count
#  4. Explicit via --source-group
def detect_source_group(project, target_name, explicit: nil)
  return explicit if explicit

  project_name = File.basename(project.path, ".xcodeproj")

  candidates = project.main_group.children.select { |c|
    c.is_a?(Xcodeproj::Project::Object::PBXGroup)
  }

  match = candidates.find { |c| c.path == target_name }
  return match if match

  match = candidates.find { |c| c.path == project_name }
  return match if match

  with_path = candidates.select { |c| c.path && !c.path.empty? }
  best = with_path.max_by { |c| c.children.length }
  return best if best

  names = candidates.map { |c| c.path || c.name || "(unnamed)" }.join(", ")
  abort "ERROR: Cannot auto-detect source group. Use --source-group. Available: #{names}"
end

# Remove an entire group (and optionally its descendants from build phases
# and from disk).
def remove_group(project, target, group, delete_from_disk: false, recursive: false)
  group_label = group.path || group.name || "(unnamed)"
  # Capture real_path before removal — parent chain is lost after
  # removing from the parent group.
  dir = group.real_path.to_s

  if recursive
    # Remove all descendant file refs from build phases
    descendant_file_refs(group).each do |fr|
      remove_file_ref(project, target, fr, delete_from_disk: delete_from_disk)
    end
    # Remove descendant groups from the hierarchy (bottom-up)
    remove_descendant_groups(group)
  else
    # Only remove the group if it has no descendant file refs or subgroups
    file_children = descendant_file_refs(group)
    sub_groups = group.children.select { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) }
    unless file_children.empty? && sub_groups.empty?
      parts = []
      parts << "files: #{file_children.map { |f| File.basename(f.real_path.to_s) }.join(', ')}" unless file_children.empty?
      parts << "subgroups: #{sub_groups.map { |g| g.path || g.name || '(unnamed)' }.join(', ')}" unless sub_groups.empty?
      abort "ERROR: Group '#{group_label}' is not empty (#{parts.join('; ')}). Use --recursive to remove contents as well."
    end
  end

  # Remove from parent group
  parent = find_parent_group(project, group)
  if parent
    parent.children.delete(group)
    parent_label = parent.path || parent.name || "root"
    log "Removed group '#{group_label}' from parent '#{parent_label}'"
  end

  # Optionally delete directory from disk
  if delete_from_disk
    if Dir.exist?(dir)
      FileUtils.rm_rf(dir)
      log "Deleted directory: #{dir}"
    else
      warn "Directory not found on disk: #{dir}"
    end
  end

  log "Removed group: #{group_label}"
end

# Remove all descendant PBXGroup objects from a group, bottom-up.
def remove_descendant_groups(group)
  sub_groups = group.children.select { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) }
  sub_groups.each { |sub| remove_descendant_groups(sub) }
  sub_groups.each do |sub|
    group.children.delete(sub)
    sub_label = sub.path || sub.name || "(unnamed)"
    log "Removed subgroup: #{sub_label}"
  end
end

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

options = {
  project:      nil,
  target:       nil,
  source_group: nil,
  group:        "",
  files:        [],
  dry_run:      false,
  delete_files: false,
  delete_group: false,
  recursive:    false,
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby xcode_remove_files.rb [options] [files...]"

  opts.on("--project PATH", "Path to .xcodeproj (required)")  { |v| options[:project] = v }
  opts.on("--target NAME",  "Target name (required)")         { |v| options[:target] = v }
  opts.on("--source-group PATH", "Explicit source group path under main group") { |v| options[:source_group] = v }
  opts.on("--group PATH",   "Group path in Xcode navigator to remove (e.g. 'Features/Login')") { |v| options[:group] = v }
  opts.on("--files a,b,c", Array, "Comma-separated file paths to remove from project") { |v| options[:files] = v }
  opts.on("--delete-files", "Also delete removed files from disk")  { options[:delete_files] = true }
  opts.on("--delete-group", "Also delete the group directory from disk") { options[:delete_group] = true }
  opts.on("--recursive",    "With --group: also remove all descendant files and subgroups") { options[:recursive] = true }
  opts.on("--dry-run",      "Preview without modifying the project") { options[:dry_run] = true }
  opts.on("-h", "--help",   "Show this help") { puts opts; exit 0 }
end

parser.parse!
options[:files] += ARGV unless ARGV.empty?

# Validation
abort "ERROR: --project is required"  unless options[:project]
abort "ERROR: --target is required"   unless options[:target]

removing_group = !options[:group].empty?
removing_files = !options[:files].empty?

# Check flag misuse before checking for missing action
if options[:recursive] && !removing_group
  abort "ERROR: --recursive only makes sense with --group"
end

if options[:delete_group] && !removing_group
  abort "ERROR: --delete-group only makes sense with --group"
end

if options[:delete_files] && removing_group
  abort "ERROR: --delete-files is for --files, not --group. Use --delete-group for groups."
end

unless removing_group || removing_files
  $stderr.puts "ERROR: No files or group specified. Use --files or --group."
  $stderr.puts parser.help
  exit 1
end

# Resolve project
project_path = File.expand_path(options[:project], Dir.pwd)
abort "ERROR: Project not found: #{project_path}" unless File.directory?(project_path)

log "Project:  #{project_path}"
log "Target:   #{options[:target]}"
log "Group:    #{options[:group].empty? ? '(root)' : options[:group]}" if removing_group
log "Dry-run:  yes" if options[:dry_run]
log ""

project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == options[:target] }
abort "ERROR: Target '#{options[:target]}' not found. Available: #{project.targets.map(&:name).join(', ')}" unless target

source_group = detect_source_group(project, options[:target], explicit: options[:source_group])

if removing_group
  components = options[:group].split("/").reject(&:empty?)
  group = find_group_at_path(source_group, components)

  unless group
    abort "ERROR: Group not found: #{options[:group]}"
  end

  if options[:dry_run]
    log "[DRY-RUN] Would remove group: #{options[:group]}"
    log "[DRY-RUN]   Recursive: #{options[:recursive]}"
    log "[DRY-RUN]   Delete directory: #{options[:delete_group]}"
  else
    remove_group(project, target, group,
                 delete_from_disk: options[:delete_group],
                 recursive: options[:recursive])
  end
end

if removing_files
  options[:files].each do |f|
    file_abs = File.expand_path(f, Dir.pwd)
    file_basename = File.basename(f)

    if options[:dry_run]
      log "[DRY-RUN] Would remove from project: #{file_basename}"
      log "[DRY-RUN]   Delete from disk: #{options[:delete_files]}" if options[:delete_files]
      next
    end

    # Find the PBXFileReference
    all_refs = project.main_group.recursive_children.select { |c|
      c.is_a?(Xcodeproj::Project::Object::PBXFileReference)
    }
    file_ref = all_refs.find { |fr| fr.real_path.to_s == file_abs }

    unless file_ref
      warn "Not found in project: #{file_basename}"
      next
    end

    log "Processing: #{file_basename}"
    remove_file_ref(project, target, file_ref, delete_from_disk: options[:delete_files])
  end
end

if options[:dry_run]
  log ""
  log "Dry-run complete — no changes were made."
else
  project.save
  log ""
  log "Project saved."
end
