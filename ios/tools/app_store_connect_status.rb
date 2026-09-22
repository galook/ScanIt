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

token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch("APP_STORE_CONNECT_KEY_ID"),
  issuer_id: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID"),
  filepath: ENV.fetch("APP_STORE_CONNECT_KEY_FILE")
)
Spaceship::ConnectAPI.token = token

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
age_rating = app_info&.fetch_age_rating_declaration
review = begin
  version.fetch_app_store_review_detail
rescue RuntimeError => error
  raise unless error.message == "No data"

  nil
end

localizations = version.get_app_store_version_localizations.sort_by(&:locale).map do |localization|
  sets = localization.get_app_screenshot_sets(includes: "appScreenshots")
  {
    locale: localization.locale,
    screenshot_count: sets.sum { |set| set.app_screenshots&.length.to_i },
    screenshot_sets: sets.sort_by(&:screenshot_display_type).to_h do |set|
      [set.screenshot_display_type, set.app_screenshots&.length.to_i]
    end,
    metadata: {
      description: !localization.description.to_s.empty?,
      keywords: !localization.keywords.to_s.empty?,
      marketing_url: localization.marketing_url,
      promotional_text: !localization.promotional_text.to_s.empty?,
      support_url: localization.support_url,
      whats_new: !localization.whats_new.to_s.empty?
    }
  }
end

client = Spaceship::ConnectAPI.tunes_request_client

availability = begin
  record = client.get("/v2/appAvailabilities/#{app.id}", {}).body.fetch("data")
  params = client.build_params(filter: nil, includes: "territory", limit: 200, sort: nil)
  territories = client.get("/v2/appAvailabilities/#{app.id}/territoryAvailabilities", params).body.fetch("data")
  {
    available_in_new_territories: record.dig("attributes", "availableInNewTerritories"),
    territory_count: territories.length,
    available_territory_count: territories.count { |territory| territory.dig("attributes", "available") },
    unavailable_territories: territories.reject { |territory| territory.dig("attributes", "available") }.map do |territory|
      {
        id: territory.dig("relationships", "territory", "data", "id") || territory.fetch("id"),
        content_statuses: territory.dig("attributes", "contentStatuses")
      }
    end
  }
rescue StandardError => error
  { error: "#{error.class}: #{error.message}" }
end

prices = begin
  params = client.build_params(filter: nil, includes: "appPricePoint", limit: 200, sort: nil)
  response = client.get("/v1/appPriceSchedules/#{app.id}/manualPrices", params).body
  points = (response["included"] || []).to_h { |point| [point.fetch("id"), point] }
  response.fetch("data").map do |price|
    point_id = price.dig("relationships", "appPricePoint", "data", "id")
    {
      id: price.fetch("id"),
      customer_price: points.dig(point_id, "attributes", "customerPrice"),
      start_date: price.dig("attributes", "startDate"),
      end_date: price.dig("attributes", "endDate")
    }
  end
rescue StandardError => error
  { error: "#{error.class}: #{error.message}" }
end

build = version.build
status = {
  app: {
    id: app.id,
    name: app.name,
    bundle_id: app.bundle_id,
    sku: app.sku,
    primary_locale: app.primary_locale,
    content_rights_declaration: app.content_rights_declaration
  },
  app_info: {
    id: app_info&.id,
    state: app_info&.state,
    primary_category: app_info&.primary_category&.id,
    secondary_category: app_info&.secondary_category&.id,
    app_store_age_rating: app_info&.app_store_age_rating
  },
  age_rating: age_rating && JSON.parse(age_rating.to_json),
  version: {
    id: version.id,
    version_string: version.version_string,
    state: version.app_version_state,
    release_type: version.release_type,
    copyright: version.copyright,
    build: build && {
      id: build.id,
      version: build.version,
      processing_state: build.processing_state,
      uses_non_exempt_encryption: build.uses_non_exempt_encryption
    }
  },
  localizations: localizations,
  review: {
    exists: !review.nil?,
    contact_first_name: review&.contact_first_name,
    contact_last_name: review&.contact_last_name,
    contact_email: review&.contact_email,
    contact_phone_present: !review&.contact_phone.to_s.empty?,
    demo_account_required: review&.demo_account_required,
    notes_present: !review&.notes.to_s.empty?
  },
  availability: availability,
  prices: prices
}

puts JSON.pretty_generate(status)
