#!/usr/bin/env ruby
# frozen_string_literal: true

# xcode_add_files.rb — Safely add source/resource files and groups to an
# Xcode project (.pbxproj).
#
# Uses the xcodeproj gem (available wherever CocoaPods or Fastlane is
# installed) to manipulate the .pbxproj.  UUID generation, cross-referencing,
# and format preservation are all handled — this is the same library
# CocoaPods itself uses internally.
#
# === Add files ===
#   ruby xcode_add_files.rb \
#     --project MyApp.xcodeproj \
#     --target MyApp \
#     --group "Features/Login" \
#     --files MyApp/Features/Login/LoginVC.m MyApp/Features/Login/LoginVC.h
#
# === Create an empty group (mapped to a real directory) ===
#   ruby xcode_add_files.rb \
#     --project MyApp.xcodeproj \
#     --target MyApp \
#     --group "Features/Settings" \
#     --create-group
#
# === Create an empty logical group (no filesystem directory) ===
#   ruby xcode_add_files.rb \
#     --project MyApp.xcodeproj \
#     --target MyApp \
#     --group "Vendor" \
#     --create-group --logical
#
# The script is idempotent — re-running with the same arguments is safe.
# Use --dry-run to preview.

require "xcodeproj"
require "optparse"
require "pathname"
require "fileutils"

# ---------------------------------------------------------------------------
# File-type detection
# ---------------------------------------------------------------------------

FILE_TYPE_MAP = {
  ".m"         => ["sourcecode.c.objc",       :sources],
  ".mm"        => ["sourcecode.cpp.objcpp",    :sources],
  ".swift"     => ["sourcecode.swift",         :sources],
  ".c"         => ["sourcecode.c.c",           :sources],
  ".cpp"       => ["sourcecode.cpp.cpp",       :sources],
  ".cc"        => ["sourcecode.cpp.cpp",       :sources],
  ".cxx"       => ["sourcecode.cpp.cpp",       :sources],
  ".metal"     => ["sourcecode.metal",         :sources],
  ".h"         => ["sourcecode.c.h",           :headers],
  ".hpp"       => ["sourcecode.cpp.h",         :headers],
  ".pch"       => ["sourcecode.c.h",           :sources],
  ".plist"     => ["text.plist.xml",           :resources],
  ".json"      => ["text.json",                :resources],
  ".storyboard"=> ["file.storyboard",          :resources],
  ".xib"       => ["file.xib",                 :resources],
  ".xcassets"  => ["folder.assetcatalog",      :resources],
  ".png"       => ["image.png",                :resources],
  ".jpg"       => ["image.jpeg",               :resources],
  ".jpeg"      => ["image.jpeg",               :resources],
  ".gif"       => ["image.gif",                :resources],
  ".pdf"       => ["image.pdf",                :resources],
  ".ttf"       => ["file",                     :resources],
  ".otf"       => ["file",                     :resources],
  ".strings"   => ["text.plist.strings",       :resources],
  ".rtf"       => ["text.rtf",                 :resources],
  ".bundle"    => ["wrapper.plug-in",          :resources],
  ".framework" => ["wrapper.framework",        nil],       # manual link
  ".dylib"     => ["compiled.mach-o.dylib",    nil],       # manual link
  ".tbd"       => ["sourcecode.text-based-dylib-definition", nil],
  ".a"         => ["archive.ar",               nil],       # manual link
  ".xcdatamodeld" => ["wrapper.xcdatamodeld",  :resources],
  ".mlmodel"   => ["file.mlmodel",             :sources],
  ".intentdefinition" => ["file.intentdefinition", :sources],
}.freeze

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def file_type_for(path)
  ext = File.extname(path).downcase
  FILE_TYPE_MAP[ext] || (abort "ERROR: Unknown file type for '#{ext}' — #{path}")
end

def log(msg)
  $stderr.puts "  #{msg}"
end

# Find or lazily create a subgroup path under `parent_group`.
def find_or_create_group(project, parent_group, components)
  components.each do |segment|
    existing = parent_group.children.find { |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.path == segment
    }
    if existing
      parent_group = existing
    else
      new_group = project.new(Xcodeproj::Project::Object::PBXGroup)
      new_group.path = segment
      new_group.source_tree = "<group>"
      parent_group.children << new_group
      parent_group = new_group
      log "Created group: #{segment}"
    end
  end
  parent_group
end

# Create an empty group (with or without filesystem directory mapping).
def create_empty_group(project, base_group, group_components, logical: false)
  leaf_name = group_components.pop
  parent = find_or_create_group(project, base_group, group_components)

  # Check if already exists
  existing = parent.children.find { |c|
    c.is_a?(Xcodeproj::Project::Object::PBXGroup) &&
      (logical ? c.name == leaf_name : c.path == leaf_name)
  }
  if existing
    log "Group already exists: #{leaf_name}"
    return existing
  end

  group = project.new(Xcodeproj::Project::Object::PBXGroup)
  group.source_tree = "<group>"

  if logical
    group.name = leaf_name
    group.path = nil
    log "Created logical group (no directory): #{leaf_name}"
  else
    group.path = leaf_name
    # Also create the directory on disk
    dir = File.join(parent.real_path, leaf_name)
    FileUtils.mkdir_p(dir)
    log "Created directory: #{dir}"
    log "Created group: #{leaf_name}"
  end

  parent.children << group
  group
end

def add_file_to_project(project, target, base_group, group_path, file_abs, dry_run: false)
  unless File.exist?(file_abs)
    $stderr.puts "WARNING: File does not exist on disk — skipping: #{file_abs}"
    return
  end

  last_known_type, phase = file_type_for(file_abs)
  file_basename = File.basename(file_abs)

  # Idempotency: check if already referenced via real_path
  expanded = File.expand_path(file_abs)
  all_refs = project.main_group.recursive_children.select { |c|
    c.is_a?(Xcodeproj::Project::Object::PBXFileReference)
  }
  existing_ref = all_refs.find { |f| f.real_path.to_s == expanded }

  if existing_ref
    already = case phase
              when :sources   then target.source_build_phase.files.any? { |bf| bf.file_ref == existing_ref }
              when :resources then target.resources_build_phase.files.any? { |bf| bf.file_ref == existing_ref }
              when :headers   then target.headers_build_phase&.files&.any? { |bf| bf.file_ref == existing_ref }
              else true
              end
    if already
      log "Already in project and build phase: #{file_basename}"
    else
      log "File ref exists but not in build phase — adding: #{file_basename}"
      add_to_build_phase(target, existing_ref, phase, dry_run: dry_run)
    end
    return
  end

  if dry_run
    log "[DRY-RUN] Would add: #{file_basename}  (#{last_known_type}, #{phase})"
    return
  end

  file_ref = project.new(Xcodeproj::Project::Object::PBXFileReference)
  file_ref.path = file_basename
  file_ref.last_known_file_type = last_known_type
  file_ref.source_tree = "<group>"

  group_components = group_path.split("/").reject(&:empty?)
  target_group = find_or_create_group(project, base_group, group_components)
  target_group.children << file_ref

  log "Added file ref: #{file_basename}"
  add_to_build_phase(target, file_ref, phase, dry_run: dry_run)
end

def add_to_build_phase(target, file_ref, phase, dry_run: false)
  return if dry_run

  case phase
  when :sources
    target.source_build_phase.add_file_reference(file_ref)
    log "Added to Sources"
  when :resources
    target.resources_build_phase.add_file_reference(file_ref)
    log "Added to Resources"
  when :headers
    target.headers_build_phase ||= target.build_phases <<
      target.project.new(Xcodeproj::Project::Object::PBXHeadersBuildPhase)
    target.headers_build_phase.add_file_reference(file_ref)
    log "Added to Headers"
  when nil
    log "Skipped build phase (link manually if needed)"
  end
end

# Try to locate the source root group — the group under main_group
# that contains the project's actual source tree.  Common patterns:
#   1. path == target_name   (e.g. "MyApp" group when target is "MyApp")
#   2. path == project_name  (derived from .xcodeproj name)
#   3. First group with path != nil and many children
#   4. User-specified via --source-group
def detect_source_group(project, target_name, explicit: nil)
  return explicit if explicit

  project_name = File.basename(project.path, ".xcodeproj")

  candidates = project.main_group.children.select { |c|
    c.is_a?(Xcodeproj::Project::Object::PBXGroup)
  }

  # 1. path matches target name
  match = candidates.find { |c| c.path == target_name }
  return match if match

  # 2. path matches project name
  match = candidates.find { |c| c.path == project_name }
  return match if match

  # 3. largest group by children count (heuristic)
  with_path = candidates.select { |c| c.path && !c.path.empty? }
  best = with_path.max_by { |c| c.children.length }
  return best if best

  # 4. give up and list what's available
  names = candidates.map { |c| c.path || c.name || "(unnamed)" }.join(", ")
  abort "ERROR: Cannot auto-detect source group. Use --source-group. Available: #{names}"
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
  create_group: false,
  logical:      false,
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby xcode_add_files.rb [options] [files...]"

  opts.on("--project PATH", "Path to .xcodeproj (required)")  { |v| options[:project] = v }
  opts.on("--target NAME",  "Target name (required)")         { |v| options[:target] = v }
  opts.on("--source-group PATH", "Explicit source group path under main group") { |v| options[:source_group] = v }
  opts.on("--group PATH",   "Group path in Xcode navigator (e.g. 'Features/Login')") { |v| options[:group] = v }
  opts.on("--files a,b,c", Array, "Comma-separated file paths") { |v| options[:files] = v }
  opts.on("--create-group", "Create an empty group (no files)") { options[:create_group] = true }
  opts.on("--logical",      "With --create-group: create logical group (no directory on disk)") { options[:logical] = true }
  opts.on("--dry-run",      "Preview without modifying the project") { options[:dry_run] = true }
  opts.on("-h", "--help",   "Show this help") { puts opts; exit 0 }
end

parser.parse!
options[:files] += ARGV unless ARGV.empty?

# Validation
abort "ERROR: --project is required"  unless options[:project]
abort "ERROR: --target is required"   unless options[:target]

if options[:create_group]
  abort "ERROR: --logical only makes sense with --create-group" if options[:logical] && !options[:create_group]
  abort "ERROR: --group is required with --create-group" if options[:group].empty?
elsif options[:files].empty?
  $stderr.puts "ERROR: No files specified. Use --files or --create-group."
  $stderr.puts parser.help
  exit 1
end

# Resolve project
project_path = File.expand_path(options[:project], Dir.pwd)
abort "ERROR: Project not found: #{project_path}" unless File.directory?(project_path)

log "Project:  #{project_path}"
log "Target:   #{options[:target]}"
log "Group:    #{options[:group].empty? ? '(root)' : options[:group]}"
log "Dry-run:  yes" if options[:dry_run]
log ""

project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == options[:target] }
abort "ERROR: Target '#{options[:target]}' not found. Available: #{project.targets.map(&:name).join(', ')}" unless target

source_group = detect_source_group(project, options[:target], explicit: options[:source_group])

if options[:create_group]
  components = options[:group].split("/").reject(&:empty?)
  if options[:dry_run]
    log "[DRY-RUN] Would create #{options[:logical] ? 'logical' : 'directory'} group: #{options[:group]}"
  else
    create_empty_group(project, source_group, components, logical: options[:logical])
  end
else
  options[:files].each do |f|
    file_abs = File.expand_path(f, Dir.pwd)
    log "Processing: #{File.basename(f)}"
    add_file_to_project(project, target, source_group, options[:group], file_abs, dry_run: options[:dry_run])
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
