#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "dotenv"
require "spaceship"

ios_root = File.expand_path("..", __dir__)
Dotenv.load(File.join(ios_root, ".env.appstore"))

required = %w[
  APP_STORE_CONNECT_KEY_ID
  APP_STORE_CONNECT_ISSUER_ID
  APP_STORE_CONNECT_KEY_FILE
]
missing = required.reject { |name| ENV[name] && !ENV[name].empty? }
abort("Missing App Store Connect settings: #{missing.join(', ')}") unless missing.empty?

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch("APP_STORE_CONNECT_KEY_ID"),
  issuer_id: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID"),
  filepath: ENV.fetch("APP_STORE_CONNECT_KEY_FILE")
)

bundle_id = ENV.fetch("APP_IDENTIFIER", "com.majkeylab.seliascan")
version_string = ENV.fetch("MARKETING_VERSION", "2.0")
app = Spaceship::ConnectAPI::App.find(bundle_id)
abort("App not found for bundle ID #{bundle_id}") unless app

version = app.get_app_store_versions(
  filter: { platform: "IOS", versionString: version_string },
  includes: "build"
).first
abort("App Store version #{version_string} not found") unless version

app_info = app.fetch_edit_app_info || app.fetch_latest_app_info
abort("Editable app information not found") unless app_info

app.update(attributes: {
  contentRightsDeclaration: Spaceship::ConnectAPI::App::ContentRightsDeclaration::DOES_NOT_USE_THIRD_PARTY_CONTENT
})

app_info.update_categories(category_id_map: {
  primary_category_id: "PRODUCTIVITY",
  secondary_category_id: "UTILITIES"
})

rating_path = File.join(ios_root, "fastlane/metadata/app_rating_config.json")
rating_attributes = JSON.parse(File.read(rating_path)).to_h do |key, value|
  api_key = Spaceship::ConnectAPI::AgeRatingDeclaration.map_key_from_itc(key)
  api_value = Spaceship::ConnectAPI::AgeRatingDeclaration.map_value_from_itc(api_key, value)
  [api_key, api_value]
end
rating_attributes, _messages, errors = Spaceship::ConnectAPI::AgeRatingDeclaration.map_deprecation_if_possible(rating_attributes)
abort(errors.join("\n")) unless errors.empty?
app_info.fetch_age_rating_declaration.update(attributes: rating_attributes)

version.update(attributes: {
  releaseType: "MANUAL",
  copyright: "2026 Matěj Teplý"
})
if version.build && version.build.uses_non_exempt_encryption.nil?
  version.build.update(attributes: { usesNonExemptEncryption: false })
end

client = Spaceship::ConnectAPI.tunes_request_client

manual_prices = begin
  client.get("/v1/appPriceSchedules/#{app.id}/manualPrices", {}).body.fetch("data")
rescue Spaceship::UnexpectedResponse => error
  raise unless error.message.include?("There is no resource of type 'null'")

  []
end

if manual_prices.empty?
  params = client.build_params(filter: { territory: "USA" }, includes: nil, limit: 200, sort: nil)
  price_points = client.get("/v1/apps/#{app.id}/appPricePoints", params).body.fetch("data")
  free_price_point = price_points.find { |point| point.dig("attributes", "customerPrice").to_f.zero? }
  abort("Free USA app price point not found") unless free_price_point

  local_price_id = "${fruityselia-free-price}"
  client.post("/v1/appPriceSchedules", {
    data: {
      type: "appPriceSchedules",
      relationships: {
        app: { data: { type: "apps", id: app.id } },
        baseTerritory: { data: { type: "territories", id: "USA" } },
        manualPrices: { data: [{ type: "appPrices", id: local_price_id }] }
      }
    },
    included: [{
      type: "appPrices",
      id: local_price_id,
      relationships: {
        appPricePoint: { data: { type: "appPricePoints", id: free_price_point.fetch("id") } }
      }
    }]
  })
end

availability_exists = begin
  client.get("/v2/appAvailabilities/#{app.id}", {})
  true
rescue Spaceship::UnexpectedResponse => error
  raise unless error.message.include?("There is no resource of type 'appAvailabilities'")

  false
end


unless availability_exists
  territory_params = client.build_params(filter: nil, includes: nil, limit: 200, sort: nil)
  territories = client.get("/v1/territories", territory_params).body.fetch("data")
  relationships = []
  included = territories.map do |territory|
    territory_id = territory.fetch("id")
    local_id = "${availability-#{territory_id}}"
    relationships << { type: "territoryAvailabilities", id: local_id }
    {
      type: "territoryAvailabilities",
      id: local_id,
      attributes: { available: true, preOrderEnabled: false },
      relationships: {
        territory: { data: { type: "territories", id: territory_id } }
      }
    }
  end

  client.post("/v2/appAvailabilities", {
    data: {
      type: "appAvailabilities",
      attributes: { availableInNewTerritories: true },
      relationships: {
        app: { data: { type: "apps", id: app.id } },
        territoryAvailabilities: { data: relationships }
      }
    },
    included: included
  })
end

phone = ENV["APP_REVIEW_PHONE"].to_s.strip
review_attributes = {
  contactFirstName: File.read(File.join(ios_root, "fastlane/metadata/review_information/first_name.txt")).strip,
  contactLastName: File.read(File.join(ios_root, "fastlane/metadata/review_information/last_name.txt")).strip,
  contactEmail: File.read(File.join(ios_root, "fastlane/metadata/review_information/email_address.txt")).strip,
  contactPhone: phone,
  demoAccountRequired: false,
  notes: File.read(File.join(ios_root, "fastlane/metadata/review_information/notes.txt")).strip
}

if phone.empty?
  warn("Reviewer phone not configured; review contact remains unchanged.")
else
  review = begin
    version.fetch_app_store_review_detail
  rescue RuntimeError => error
    raise unless error.message == "No data"

    nil
  end
  review ? review.update(attributes: review_attributes) : version.create_app_store_review_detail(attributes: review_attributes)
end

puts("App Store Connect configuration applied for #{bundle_id} version #{version_string}.")
