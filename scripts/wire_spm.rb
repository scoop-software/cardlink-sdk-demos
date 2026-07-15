#!/usr/bin/env ruby
# wire_spm.rb — Wire an Xcode project to consume the Cardlink + NFC SDKs via SPM.
#
# Usage:
#   ruby scripts/wire_spm.rb <project.xcodeproj> --remote
#   ruby scripts/wire_spm.rb <project.xcodeproj> --local <cardlink-dev-spm-path> [<nfc-dev-spm-path>]
#
# In --remote mode, Cardlink and NFC products use separate Gitea registry
# identities. In --local mode, cardlink is wired as a
# local path-based package; nfc is also wired locally if a second path is
# supplied, otherwise it falls back to the remote registry package.
#
# Idempotent: running twice produces no second commit.
require 'xcodeproj'

project_path = ARGV[0] or abort "usage: wire_spm.rb <project.xcodeproj> --remote | --local <cardlink-path> [<nfc-path>]"
mode         = ARGV[1]
cardlink_local_path = ARGV[2]
nfc_local_path      = ARGV[3]
abort "second arg must be --remote or --local" unless ['--remote', '--local'].include?(mode)
abort "--local needs a cardlink path" if mode == '--local' && cardlink_local_path.nil?

PACKAGES = [
  {
    target_product_names: ['ScoopCardlink'],
    remote_repo_url:      'ti-cardlink.cardlink',
    remote_min_version:   '2.6.2',
    local_path_marker:    'cardlink-sdk',
  },
  {
    target_product_names: ['ScoopNfc', 'ScoopNfcUI'],
    remote_repo_url:      'ti-common.nfc',
    remote_min_version:   '2.3.2',
    local_path_marker:    'scoop-nfc-sdk',
  },
].freeze

project = Xcodeproj::Project.open(project_path)
target  = project.targets.find { |t| t.name == 'CardlinkDemo' } \
  or abort "Could not find target 'CardlinkDemo' in #{project_path}"

# ── 1. Remove the vendored xcframework references ──
# The SPM packages ship these as binary targets; the demo no longer needs
# direct file references.
VENDORED_XCFRAMEWORKS = %w[
  CardlinkSDK.xcframework
  ScoopCardlink.xcframework
  ScoopNfc.xcframework
].freeze

def vendored?(path)
  return false if path.nil?
  VENDORED_XCFRAMEWORKS.any? { |name| path.include?(name) }
end

project.files.select { |f| vendored?(f.path) }.each do |ref|
  puts "  removing file reference: #{ref.path}"
  ref.remove_from_project
end

# Also remove any frameworks/embed build-phase entries pointing at them
# across ALL native targets (otherwise dangling build-file refs survive).
# IMPORTANT: don't touch entries whose product_ref is set — those are SPM
# package products (e.g. Lottie) and must be preserved.
project.native_targets.each do |t|
  t.frameworks_build_phase.files.dup.each do |bf|
    next if bf.product_ref
    if bf.file_ref.nil? || vendored?(bf.file_ref.path)
      puts "  removing frameworks-phase entry (#{t.name}): #{bf.display_name}"
      bf.remove_from_project
    end
  end
  t.copy_files_build_phases.each do |phase|
    phase.files.dup.each do |bf|
      next if bf.product_ref
      if bf.file_ref.nil? || vendored?(bf.file_ref.path)
        puts "  removing embed-phase entry (#{t.name}): #{bf.display_name}"
        bf.remove_from_project
      end
    end
  end
end

# ── 2. Wire each package: ensure SPM reference + product link ──
def wire_package(project, target, package, mode, local_path)
  remote_repo = package[:remote_repo_url]
  marker      = package[:local_path_marker]

  existing_remote = project.root_object.package_references.find do |ref|
    ref.is_a?(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference) &&
      ref.repositoryURL.include?(File.basename(remote_repo, '.git'))
  end
  existing_local = project.root_object.package_references.find do |ref|
    ref.is_a?(Xcodeproj::Project::Object::XCLocalSwiftPackageReference) &&
      ref.relative_path.to_s.include?(marker)
  end

  use_local = (mode == '--local') && !local_path.nil?

  if use_local
    if existing_remote
      puts "  removing existing remote package reference: #{existing_remote.repositoryURL}"
      existing_remote.remove_from_project
      project.root_object.package_references.delete(existing_remote)
    end
    package_ref = existing_local
    unless package_ref
      package_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
      package_ref.relative_path = local_path
      project.root_object.package_references << package_ref
      puts "  added local package: #{local_path}"
    end
  else
    if existing_local
      puts "  removing existing local package reference: #{existing_local.relative_path}"
      existing_local.remove_from_project
      project.root_object.package_references.delete(existing_local)
    end
    package_ref = existing_remote
    unless package_ref
      package_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
      package_ref.repositoryURL = remote_repo
      package_ref.requirement = { 'kind' => 'exactVersion', 'version' => package[:remote_min_version] }
      project.root_object.package_references << package_ref
      puts "  added remote package: #{package_ref.repositoryURL}"
    end
    desired_requirement = { 'kind' => 'exactVersion', 'version' => package[:remote_min_version] }
    if package_ref.requirement != desired_requirement
      package_ref.requirement = desired_requirement
      puts "  pinned #{package_ref.repositoryURL} at #{package[:remote_min_version]}"
    end
  end

  package[:target_product_names].each do |product_name|
    existing_dep = target.package_product_dependencies.find { |d| d.product_name == product_name }
    if existing_dep
      # Re-point the dep at the (possibly new) package ref. This handles the
      # mode-switch case (duplicating CardlinkDemo → CardlinkDemoDev and then
      # re-running with --local): the product dep already exists but still
      # references the removed remote package; we need to rebind it.
      if existing_dep.package != package_ref
        existing_dep.package = package_ref
        puts "  rebound #{product_name} product to current package ref"
      end
      next
    end
    product_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    product_dep.package = package_ref
    product_dep.product_name = product_name
    target.package_product_dependencies << product_dep

    # PBXBuildFile for an SPM product uses product_ref (not file_ref).
    # add_file_reference rejects XCSwiftPackageProductDependency, so we build
    # the PBXBuildFile manually and append it to the frameworks build phase.
    build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    build_file.product_ref = product_dep
    target.frameworks_build_phase.files << build_file
    puts "  linked #{product_name} product to target"
  end
end

wire_package(project, target, PACKAGES[0], mode, cardlink_local_path)
wire_package(project, target, PACKAGES[1], mode, nfc_local_path)

# The former umbrella package can remain as an unused root reference after its
# products are rebound to the separate Cardlink and NFC registry packages.
used_package_refs = project.targets
  .flat_map(&:package_product_dependencies)
  .map(&:package)
  .compact
project.root_object.package_references.dup.each do |ref|
  next unless ref.is_a?(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  next unless ref.repositoryURL.to_s.include?('cardlink-packages')
  next if used_package_refs.include?(ref)

  puts "  removing unused legacy package reference: #{ref.repositoryURL}"
  ref.remove_from_project
  project.root_object.package_references.delete(ref)
end

project.save
puts "Saved #{project_path}"
