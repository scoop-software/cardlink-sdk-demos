#!/usr/bin/env ruby
# swap_xcconfig.rb — swap the Debug-config xcconfig file for a project.
#
# Used by Task 5 of the Phase 2 iOS demo migration plan to point
# CardlinkDemoDev.xcodeproj's Debug configuration at Debug-Dev.xcconfig
# (which sets a distinct bundle ID and product name for side-by-side
# install alongside the customer-facing CardlinkDemo build).
#
# Usage:
#   ruby scripts/swap_xcconfig.rb <project.xcodeproj> <new-xcconfig-name>

require 'xcodeproj'

project_path = ARGV[0] or abort "usage: swap_xcconfig.rb <project.xcodeproj> <new-xcconfig-name>"
new_name = ARGV[1] or abort "usage: swap_xcconfig.rb <project.xcodeproj> <new-xcconfig-name>"

project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'CardlinkDemo' } \
  or abort "Could not find target 'CardlinkDemo'"

new_ref = project.files.find { |f| f.path == new_name }
unless new_ref
  sample_group = project.main_group.find_subpath('CardlinkSample', false)
  abort "Could not find CardlinkSample group" unless sample_group
  # The CardlinkSample group already has path=CardlinkSample, so the file's
  # path is relative to that group — just the basename, not a sub-path.
  new_ref = sample_group.new_file(new_name)
end

target.build_configurations.each do |config|
  if config.name == 'Debug'
    config.base_configuration_reference = new_ref
    puts "  Debug config base reference → #{new_name}"
  end
end

project.save
puts "Saved #{project_path}"
