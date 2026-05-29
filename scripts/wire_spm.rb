#!/usr/bin/env ruby
# wire_spm.rb — Wire an Xcode project to consume ScoopCardlink via SPM.
#
# Usage:
#   ruby scripts/wire_spm.rb <project.xcodeproj> --remote
#   ruby scripts/wire_spm.rb <project.xcodeproj> --local <path-to-local-package-dir>
#
# Idempotent: running twice produces no second commit.
require 'xcodeproj'

project_path = ARGV[0] or abort "usage: wire_spm.rb <project.xcodeproj> --remote | --local <path>"
mode = ARGV[1]
local_path = ARGV[2]
abort "second arg must be --remote or --local" unless ['--remote', '--local'].include?(mode)
abort "--local needs a path arg" if mode == '--local' && local_path.nil?

project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'CardlinkDemo' } \
  or abort "Could not find target 'CardlinkDemo' in #{project_path}"

# ── 1. Remove the vendored xcframework references ──
# The existing project vendors ScoopCardlink.xcframework and ScoopNfc.xcframework
# (formerly named CardlinkSDK.xcframework). The SPM package transitively re-exports
# both, so the demo no longer needs either as a direct file reference.
VENDORED_XCFRAMEWORKS = %w[
  CardlinkSDK.xcframework
  ScoopCardlink.xcframework
  ScoopNfc.xcframework
].freeze

def vendored?(path)
  return false if path.nil?
  VENDORED_XCFRAMEWORKS.any? { |name| path.include?(name) }
end

xcframework_refs = project.files.select { |f| vendored?(f.path) }
xcframework_refs.each do |ref|
  puts "  removing file reference: #{ref.path}"
  ref.remove_from_project
end
# Also remove any frameworks/embed build-phase entries pointing at them
# across ALL native targets (otherwise dangling build-file refs survive).
# IMPORTANT: don't touch entries whose product_ref is set — those are SPM
# package products (e.g. Lottie) and must be preserved.
project.native_targets.each do |t|
  t.frameworks_build_phase.files.dup.each do |bf|
    next if bf.product_ref # SPM product entry — leave alone
    if bf.file_ref.nil? || vendored?(bf.file_ref.path)
      puts "  removing frameworks-phase entry (#{t.name}): #{bf.display_name}"
      bf.remove_from_project
    end
  end
  t.copy_files_build_phases.each do |phase|
    phase.files.dup.each do |bf|
      next if bf.product_ref # preserve SPM product entries
      if bf.file_ref.nil? || vendored?(bf.file_ref.path)
        puts "  removing embed-phase entry (#{t.name}): #{bf.display_name}"
        bf.remove_from_project
      end
    end
  end
end

# ── 2. Add the SPM package reference (skip if already present in the right mode) ──
existing_remote = project.root_object.package_references.find do |ref|
  ref.is_a?(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference) &&
    ref.repositoryURL.include?('cardlink-sdk-spm')
end
existing_local = project.root_object.package_references.find do |ref|
  ref.is_a?(Xcodeproj::Project::Object::XCLocalSwiftPackageReference) &&
    ref.relative_path.to_s.include?('cardlink-sdk') && ref.relative_path.to_s.include?('dev-spm')
end

# Remove whichever package ref doesn't match the requested mode
if mode == '--remote'
  if existing_local
    puts "  removing existing local package reference"
    existing_local.remove_from_project
    project.root_object.package_references.delete(existing_local)
  end
  unless existing_remote
    ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
    ref.repositoryURL = 'https://github.com/scoop-software/cardlink-sdk-spm.git'
    ref.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => '1.38.0' }
    project.root_object.package_references << ref
    puts "  added remote package: #{ref.repositoryURL}"
    package_ref = ref
  else
    package_ref = existing_remote
  end
else
  if existing_remote
    puts "  removing existing remote package reference"
    existing_remote.remove_from_project
    project.root_object.package_references.delete(existing_remote)
  end
  unless existing_local
    ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
    ref.relative_path = local_path
    project.root_object.package_references << ref
    puts "  added local package: #{local_path}"
    package_ref = ref
  else
    package_ref = existing_local
  end
end

# ── 3. Ensure the target links the ScoopCardlink product ──
already_links = target.package_product_dependencies.any? { |d| d.product_name == 'ScoopCardlink' }
unless already_links
  product_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product_dep.package = package_ref
  product_dep.product_name = 'ScoopCardlink'
  target.package_product_dependencies << product_dep

  # PBXBuildFile for an SPM product uses product_ref (not file_ref).
  # add_file_reference rejects XCSwiftPackageProductDependency, so we build the
  # PBXBuildFile manually and append it to the frameworks build phase.
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product_dep
  target.frameworks_build_phase.files << build_file
  puts "  linked ScoopCardlink product to target"
end

project.save
puts "Saved #{project_path}"
