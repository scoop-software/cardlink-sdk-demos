#!/usr/bin/env ruby
# sync-ios-projects.rb — Keep CardlinkDemo.xcodeproj and CardlinkDemoDev.xcodeproj
# in sync for source-file membership.
#
# Source of truth: CardlinkDemo.xcodeproj (the customer-facing project).
# Target: CardlinkDemoDev.xcodeproj.
#
# Modes:
#   ruby scripts/sync-ios-projects.rb           # apply sync
#   ruby scripts/sync-ios-projects.rb --check   # read-only; exit 1 on drift
#
# What syncs: the set of source/resource files in the CardlinkDemo target's
# Sources & Resources build phases.
#
# What does NOT sync: SPM package references, build configurations, signing
# settings — those legitimately differ between the two projects.

require 'xcodeproj'
require 'set'

check_mode = ARGV.include?('--check')

ROOT = File.expand_path('..', __dir__)
SOURCE_PATH = File.join(ROOT, 'ios', 'CardlinkDemo.xcodeproj')
TARGET_PATH = File.join(ROOT, 'ios', 'CardlinkDemoDev.xcodeproj')

abort "Source project not found: #{SOURCE_PATH}" unless File.exist?(SOURCE_PATH)
abort "Target project not found: #{TARGET_PATH}" unless File.exist?(TARGET_PATH)

def source_file_paths(project_path)
  project = Xcodeproj::Project.open(project_path)
  target = project.targets.find { |t| t.name == 'CardlinkDemo' }
  abort "No CardlinkDemo target in #{project_path}" unless target
  paths = Set.new
  [target.source_build_phase, target.resources_build_phase].each do |phase|
    phase.files.each do |build_file|
      ref = build_file.file_ref
      next unless ref && ref.path
      paths << ref.real_path.to_s
    end
  end
  paths
end

source_paths = source_file_paths(SOURCE_PATH)
target_paths = source_file_paths(TARGET_PATH)

missing_in_target = source_paths - target_paths
extra_in_target = target_paths - source_paths

if missing_in_target.empty? && extra_in_target.empty?
  puts "✓ #{File.basename(TARGET_PATH)} is in sync with #{File.basename(SOURCE_PATH)}"
  exit 0
end

if check_mode
  puts "✗ Drift detected between projects:"
  missing_in_target.each { |p| puts "  MISSING in Dev: #{p.sub("#{ROOT}/", '')}" }
  extra_in_target.each   { |p| puts "  EXTRA   in Dev: #{p.sub("#{ROOT}/", '')}" }
  puts ""
  puts "Run without --check to sync, or update CardlinkDemo.xcodeproj first."
  exit 1
end

# Apply mode: copy SOURCE → TARGET. We rebuild the Dev project's Sources/Resources
# build-phase membership to exactly match the customer project's.
source_project = Xcodeproj::Project.open(SOURCE_PATH)
target_project = Xcodeproj::Project.open(TARGET_PATH)
target = target_project.targets.find { |t| t.name == 'CardlinkDemo' }

# Given a group from the source project, find/create the corresponding group
# in the target project by walking the same path of group names from main_group.
def mirror_group_path(target_project, source_group)
  ancestry = []
  g = source_group
  while g && !g.equal?(g.project.main_group)
    ancestry.unshift(g.display_name)
    g = g.parent
  end
  current = target_project.main_group
  ancestry.each do |name|
    nxt = current.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == name }
    nxt ||= current.new_group(name, name)
    current = nxt
  end
  current
end

# Locate or create a file reference in the target project that mirrors the
# source project's file ref for the same real_path. Mirroring uses the source
# file's group path and own `path` attribute so we don't accidentally double
# up directory prefixes.
def find_or_add_file_ref(target_project, source_project, real_path)
  existing = target_project.files.find { |f| f.real_path.to_s == real_path }
  return existing if existing
  source_ref = source_project.files.find { |f| f.real_path.to_s == real_path }
  abort "Source project has no file at #{real_path}" unless source_ref
  group = mirror_group_path(target_project, source_ref.parent)
  group.new_file(source_ref.path)
end

extra_in_target.each do |path|
  ref = target_project.files.find { |f| f.real_path.to_s == path }
  next unless ref
  [target.source_build_phase, target.resources_build_phase].each do |phase|
    phase.files.dup.each { |bf| bf.remove_from_project if bf.file_ref == ref }
  end
  ref.remove_from_project if target_project.files.none? { |f| f == ref }
  puts "  - removed: #{path.sub("#{ROOT}/", '')}"
end

missing_in_target.each do |path|
  ref = find_or_add_file_ref(target_project, source_project, path)
  ext = File.extname(path).downcase
  case ext
  when '.swift'
    target.source_build_phase.add_file_reference(ref) unless \
      target.source_build_phase.files.any? { |bf| bf.file_ref == ref }
  else
    target.resources_build_phase.add_file_reference(ref) unless \
      target.resources_build_phase.files.any? { |bf| bf.file_ref == ref }
  end
  puts "  + added:   #{path.sub("#{ROOT}/", '')}"
end

target_project.save
puts "✓ Synced #{File.basename(TARGET_PATH)} from #{File.basename(SOURCE_PATH)}"
