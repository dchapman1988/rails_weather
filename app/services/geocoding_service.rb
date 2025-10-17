# frozen_string_literal: true

# Converts addresses into coordinates and zip codes using OpenWeather's API
#
# Takes user input like "New York, NY" or "90210" and returns the latitude,
# longitude, and zip code needed for weather lookups. Tries multiple geocoding
# strategies to maximize success rate.
class GeocodingService
  include HTTParty
  base_uri "http://api.openweathermap.org"

  class MissingApiKeyError < StandardError; end

  # Initializes the service with the OpenWeather API key
  #
  # @raise [MissingApiKeyError] if OPENWEATHER_API_KEY environment variable is not set
  def initialize
    @api_key = ENV.fetch("OPENWEATHER_API_KEY") do
      raise MissingApiKeyError, "OPENWEATHER_API_KEY environment variable is not set"
    end
  end

  # Converts an address to geographic coordinates and zip code
  #
  # Tries multiple strategies in order:
  # 1. Direct zip code lookup if one is found in the address
  # 2. City/state geocoding if we can parse that out
  # 3. Full address geocoding as a fallback
  #
  # @param address [String] The address to geocode (city, state, zip, or full address)
  # @return [Hash] Result hash with:
  #   - :success [Boolean] Whether the geocoding was successful
  #   - :lat [Float] Latitude (if successful)
  #   - :lon [Float] Longitude (if successful)
  #   - :zip [String] Zip code (if available)
  #   - :location [String] Formatted location name with country
  #   - :error [String] Error message (if unsuccessful)
  def geocode(address)
    return error_response("Address cannot be blank") if address.blank?

    # Try zip code first - it's the most reliable
    if (zip = extract_zip_from_address(address))
      result = geocode_zip_code(zip)
      return result if result[:success]
    end

    # Try city/state next - better than full address
    if (city_state = extract_city_state(address))
      result = geocode_city_state(city_state, zip)
      return result if result[:success]
    end

    # Fall back to full address geocoding
    geocode_full_address(address, zip)
  rescue StandardError => e
    Rails.logger.error("Geocoding error: #{e.message}")
    error_response("An error occurred while geocoding the address: #{e.message}")
  end

  # Pulls out a 5-digit zip code from an address string
  #
  # @param address [String] The address string to search
  # @return [String, nil] The extracted zip code or nil if not found
  def extract_zip_from_address(address)
    address.match(/\b\d{5}\b/)&.to_s
  end

  # Extracts "City, ST" from various address formats
  #
  # Handles messy input like "6214 Stewart Rd. Leeds, AL. 35094"
  # and returns just "Leeds, AL"
  #
  # @param address [String] The address string to parse
  # @return [String, nil] The extracted city and state or nil if not found
  def extract_city_state(address)
    match = address.match(/([^,]+),\s*([A-Z]{2}|[A-Za-z\s]+?)(?:\s*\.?\s*\d{5}|$)/)
    return nil unless match

    city = clean_city_name(match[1])
    state = match[2].gsub(/^\.\s*/, "").strip

    "#{city}, #{state}"
  end

  private

  # Geocodes using just the zip code - most reliable method
  #
  # @param zip_code [String] The 5-digit zip code
  # @return [Hash] Geocoding result
  def geocode_zip_code(zip_code)
    Rails.logger.info("Attempting zip code geocoding: #{zip_code}")
    
    response = self.class.get("/geo/1.0/zip", query: {
      zip: "#{zip_code},US",
      appid: @api_key
    })

    return handle_api_error(response) unless response.success?
    return error_response("Unable to find location for zip code #{zip_code}") if response.parsed_response.empty?

    build_success_response(
      response.parsed_response["lat"],
      response.parsed_response["lon"],
      zip_code,
      "#{response.parsed_response['name']}, #{response.parsed_response['country']}"
    )
  rescue StandardError => e
    Rails.logger.warn("Zip code geocoding failed: #{e.message}")
    error_response("Unable to geocode zip code #{zip_code}")
  end

  # Geocodes using parsed city and state
  #
  # @param city_state [String] The city and state string (e.g., "Leeds, AL")
  # @param fallback_zip [String, nil] Zip code to use if reverse geocoding fails
  # @return [Hash] Geocoding result
  def geocode_city_state(city_state, fallback_zip)
    Rails.logger.info("Attempting city/state geocoding: #{city_state}")
    
    response = self.class.get("/geo/1.0/direct", query: {
      q: city_state,
      limit: 1,
      appid: @api_key
    })

    Rails.logger.info("City/state API response: #{response.code}")
    
    return error_response("Location not found") unless response.success? && response.parsed_response.any?

    location_data = response.parsed_response.first
    zip_code = extract_zip_code(location_data["lat"], location_data["lon"]) || fallback_zip

    build_success_response(
      location_data["lat"],
      location_data["lon"],
      zip_code,
      format_location_name(location_data)
    )
  end

  # Geocodes using the full address string
  #
  # @param address [String] The full address
  # @param fallback_zip [String, nil] Zip code to use if reverse geocoding fails
  # @return [Hash] Geocoding result
  def geocode_full_address(address, fallback_zip)
    Rails.logger.info("Attempting full address geocoding: #{address}")
    
    response = self.class.get("/geo/1.0/direct", query: {
      q: address,
      limit: 1,
      appid: @api_key
    })

    Rails.logger.info("Full address API response: #{response.code}")
    
    return handle_api_error(response) unless response.success?
    return error_response("Unable to find location for the provided address") if response.parsed_response.empty?

    location_data = response.parsed_response.first
    zip_code = extract_zip_code(location_data["lat"], location_data["lon"]) || fallback_zip

    build_success_response(
      location_data["lat"],
      location_data["lon"],
      zip_code,
      format_location_name(location_data)
    )
  end

  # Reverse geocodes coordinates to get a zip code
  #
  # @param lat [Float] Latitude
  # @param lon [Float] Longitude
  # @return [String, nil] Zip code if found, nil otherwise
  def extract_zip_code(lat, lon)
    response = self.class.get("/geo/1.0/reverse", query: {
      lat: lat,
      lon: lon,
      limit: 1,
      appid: @api_key
    })

    return nil unless response.success? && response.parsed_response.any?

    response.parsed_response.first["zip"]
  rescue StandardError => e
    Rails.logger.warn("Reverse geocoding failed: #{e.message}")
    nil
  end

  # Removes street address parts from city names
  #
  # @param city [String] The city name possibly containing street info
  # @return [String] Cleaned city name
  def clean_city_name(city)
    street_types = /\s+(?:Rd|Road|St|Street|Ave|Avenue|Blvd|Boulevard|Dr|Drive|Ln|Lane|Ct|Court|Pl|Place|Way|Cir|Circle)\b/i
    city.split(street_types).last.gsub(/^\.\s*/, "").strip
  end

  # Builds a human-readable location string like "New York, NY, US"
  #
  # @param location_data [Hash] The location data from the API
  # @return [String] Formatted location string
  def format_location_name(location_data)
    [
      location_data["name"],
      location_data["state"],
      location_data["country"]
    ].compact.join(", ")
  end

  # Maps HTTP status codes to user-friendly error messages
  #
  # @param response [HTTParty::Response] The API response
  # @return [Hash] Error hash with details
  def handle_api_error(response)
    message = case response.code
              when 401 then "Invalid API key"
              when 404 then "Location not found"
              when 429 then "API rate limit exceeded"
              else "API request failed with status #{response.code}"
              end

    error_response(message)
  end

  # Builds a success response hash
  #
  # @param lat [Float] Latitude
  # @param lon [Float] Longitude
  # @param zip [String] Zip code
  # @param location [String] Formatted location string
  # @return [Hash] Success response
  def build_success_response(lat, lon, zip, location)
    {
      success: true,
      lat: lat,
      lon: lon,
      zip: zip,
      location: location
    }
  end

  # Builds an error response hash
  #
  # @param message [String] The error message
  # @return [Hash] Error response
  def error_response(message)
    { success: false, error: message }
  end
end
