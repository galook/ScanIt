#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"

root = Pathname.new(__dir__).parent
metadata = root / "fastlane/metadata"
errors = []
warnings = []

required = {
  "name.txt" => 30,
  "subtitle.txt" => 30,
  "promotional_text.txt" => 170,
  "description.txt" => 4000,
  "keywords.txt" => 100,
  "release_notes.txt" => 4000,
  "privacy_url.txt" => nil,
  "support_url.txt" => nil,
  "marketing_url.txt" => nil
}.freeze

locales = %w[en-US cs de-DE es-ES zh-Hans]
locales.each do |locale|
  required.each do |filename, limit|
    path = metadata / locale / filename
    unless path.file?
      errors << "missing #{path.relative_path_from(root)}"
      next
    end
    value = path.read.strip
    errors << "empty #{path.relative_path_from(root)}" if value.empty?
    if limit && value.each_char.count > limit
      errors << "#{locale}/#{filename} is #{value.each_char.count} characters; limit #{limit}"
    end
    if filename.end_with?("_url.txt") && value !~ %r{\Ahttps://[^\s]+\z}
      errors << "#{locale}/#{filename} must be one HTTPS URL"
    end
  end
end

keywords = locales.to_h { |locale| [locale, (metadata / locale / "keywords.txt").read.strip] }
keywords.each do |locale, value|
  errors << "#{locale}/keywords.txt contains a duplicate keyword" if value.split(",").map { |word| word.strip.downcase }.then { |words| words.uniq.length != words.length }
end

review_files = %w[first_name.txt last_name.txt email_address.txt notes.txt]
review_files.each do |filename|
  path = metadata / "review_information" / filename
  errors << "missing #{path.relative_path_from(root)}" unless path.file? && !path.read.strip.empty?
end

Dir.glob((metadata / "**/*.txt").to_s).each do |filename|
  text = File.read(filename)
  errors << "placeholder remains in #{Pathname.new(filename).relative_path_from(root)}" if text.match?(/REPLACE_|TODO|TBD/)
end

warnings << "App Store name availability cannot be checked until the app record exists."
warnings << "Localized copy should receive a native-speaker review before submission."

warnings.each { |warning| warn "warning: #{warning}" }
if errors.empty?
  puts "App Store metadata structure and field limits: OK"
else
  errors.each { |error| warn "error: #{error}" }
  exit 1
end
