#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

REQUIRED_ENV = %w[
  APP_STORE_CONNECT_KEY_ID
  APP_STORE_CONNECT_ISSUER_ID
  APP_STORE_CONNECT_KEY_FILE
].freeze
PROFILE_NAMES = [
  "FruitySelia App Store",
  "FruitySelia Controls App Store"
].freeze

missing = REQUIRED_ENV.reject { |name| ENV[name] && !ENV[name].empty? }
abort("Missing App Store Connect settings: #{missing.join(', ')}") unless missing.empty?

def base64url(value)
  Base64.urlsafe_encode64(value, padding: false)
end

now = Time.now.to_i
header = { alg: "ES256", kid: ENV.fetch("APP_STORE_CONNECT_KEY_ID"), typ: "JWT" }
payload = {
  iss: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID"),
  iat: now - 30,
  exp: now + 1_200,
  aud: "appstoreconnect-v1"
}
signing_input = [header, payload].map { |part| base64url(JSON.generate(part)) }.join(".")
key = OpenSSL::PKey.read(File.binread(ENV.fetch("APP_STORE_CONNECT_KEY_FILE")))
der_signature = key.sign(OpenSSL::Digest.new("SHA256"), signing_input)
sequence = OpenSSL::ASN1.decode(der_signature)
raw_signature = sequence.value.map { |integer| integer.value.to_s(16).rjust(64, "0") }.join
token = "#{signing_input}.#{base64url([raw_signature].pack('H*'))}"

uri = URI("https://api.appstoreconnect.apple.com/v1/profiles")
uri.query = URI.encode_www_form(
  "filter[profileType]" => "IOS_APP_STORE",
  "limit" => "200"
)
request = Net::HTTP::Get.new(uri)
request["Authorization"] = "Bearer #{token}"
response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
abort("App Store Connect profile request failed: HTTP #{response.code}") unless response.is_a?(Net::HTTPSuccess)

profiles = JSON.parse(response.body).fetch("data")
destinations = [
  File.expand_path("~/Library/Developer/Xcode/UserData/Provisioning Profiles"),
  File.expand_path("~/Library/MobileDevice/Provisioning Profiles")
]
destinations.each { |destination| FileUtils.mkdir_p(destination) }

PROFILE_NAMES.each do |name|
  profile = profiles.find { |item| item.dig("attributes", "name") == name }
  abort("Missing App Store Connect profile: #{name}") unless profile

  attributes = profile.fetch("attributes")
  abort("Expired App Store Connect profile: #{name}") if Time.iso8601(attributes.fetch("expirationDate")) <= Time.now

  content = Base64.decode64(attributes.fetch("profileContent"))
  destinations.each do |destination|
    path = File.join(destination, "#{attributes.fetch('uuid')}.mobileprovision")
    File.binwrite(path, content)
    File.chmod(0o600, path)
  end
  puts "Installed #{name}: #{attributes.fetch('uuid')}"
end
