#!/usr/bin/env ruby
# Structural validation only. This does not replace Swift compilation or XCTest.
require 'json'
require 'open3'
require 'rexml/document'

root = File.expand_path('..', __dir__)
project_path = File.join(root, 'statvision.xcodeproj/project.pbxproj')
json, error, status = Open3.capture3('plutil', '-convert', 'json', '-o', '-', project_path)
abort error unless status.success?
project = JSON.parse(json)
objects = project.fetch('objects')
abort 'Missing root project' unless objects.fetch(project.fetch('rootObject'))['isa'] == 'PBXProject'

referenced_sources = []
walk = lambda do |identifier, parent|
  object = objects.fetch(identifier)
  if object['isa'] == 'PBXGroup'
    directory = object['path'] ? File.join(parent, object['path']) : parent
    object.fetch('children').each { |child| walk.call(child, directory) }
  elsif object['isa'] == 'PBXFileReference' && object['sourceTree'] == '<group>'
    path = File.join(parent, object.fetch('path'))
    abort "Missing file: #{path}" unless File.file?(path)
    referenced_sources << identifier if File.extname(path) == '.swift' && File.basename(path) != 'Package.swift'
  end
end
walk.call(objects.fetch(project.fetch('rootObject')).fetch('mainGroup'), root)

compiled_sources = objects.values.select { |o| o['isa'] == 'PBXSourcesBuildPhase' }.flat_map do |phase|
  phase.fetch('files').map { |id| objects.fetch(id).fetch('fileRef') }
end
abort 'Source target membership is incomplete or duplicated' unless compiled_sources.sort == referenced_sources.sort

scheme_path = File.join(root, 'statvision.xcodeproj/xcshareddata/xcschemes/statvision.xcscheme')
scheme = REXML::Document.new(File.read(scheme_path))
REXML::XPath.each(scheme, '//BuildableReference') do |reference|
  target = objects.fetch(reference.attributes['BlueprintIdentifier'])
  abort 'Scheme references a non-target object' unless target['isa'] == 'PBXNativeTarget'
  abort 'Scheme target name mismatch' unless target['name'] == reference.attributes['BlueprintName']
end

%w[statvision/Resources/Info.plist statvision/Resources/statvision.entitlements].each do |path|
  abort "Invalid plist: #{path}" unless system('plutil', '-lint', File.join(root, path))
end
puts "Validated: #{referenced_sources.size} Swift sources, target memberships, shared scheme and property lists."
puts 'Swift compilation and XCTest still require Xcode / the Swift toolchain.'

