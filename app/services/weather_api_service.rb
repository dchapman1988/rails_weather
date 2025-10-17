# frozen_string_literal: true

# Fetches weather data from the OpenWeather API
#
# Handles all the direct API calls to OpenWeather's Current Weather and Forecast
# endpoints. Just focuses on talking to the API and transforming the responses
# into a format our app can use - doesn't deal with caching or geocoding.
class WeatherApiService
  include HTTParty
  base_uri "http://api.openweathermap.org"

  UNITS = "imperial" # Fahrenheit
  
  class MissingApiKeyError < StandardError; end

  # Initializes the service with the OpenWeather API key
  #
  # @raise [MissingApiKeyError] if OPENWEATHER_API_KEY environment variable is not set
  def initialize
    @api_key = ENV.fetch("OPENWEATHER_API_KEY") do
      raise MissingApiKeyError, "OPENWEATHER_API_KEY environment variable is not set"
    end
  end

  # Fetches current weather conditions for a location
  #
  # Gets the current temp, conditions, humidity, wind speed - all the basics
  # you'd want to know about the weather right now.
  #
  # @param lat [Float] Latitude coordinate
  # @param lon [Float] Longitude coordinate
  # @return [Hash] Weather data with:
  #   - :success [Boolean] Whether the request was successful
  #   - :temperature [Float] Current temperature in Fahrenheit
  #   - :feels_like [Float] "Feels like" temperature
  #   - :high_temp [Float] Maximum temperature for the day
  #   - :low_temp [Float] Minimum temperature for the day
  #   - :conditions [String] Weather conditions description
  #   - :humidity [Integer] Humidity percentage
  #   - :wind_speed [Float] Wind speed in mph
  #   - :icon [String] Weather icon code
  #   - :raw_data [Hash] Complete API response for additional data
  #   - :error [String] Error message (if unsuccessful)
  def fetch_weather(lat:, lon:)
    return error_response("Latitude and longitude are required") if lat.blank? || lon.blank?

    response = make_weather_request(lat, lon)
    return handle_api_error(response) unless response.success?

    parse_weather_data(response.parsed_response)
  rescue StandardError => e
    Rails.logger.error("Weather API error: #{e.message}")
    error_response("An error occurred while fetching weather data: #{e.message}")
  end

  # Fetches extended forecast (5 days, 3-hour intervals)
  #
  # Returns detailed forecast data with multiple data points per day, giving
  # you a detailed picture of what's coming up weather-wise.
  #
  # @param lat [Float] Latitude coordinate
  # @param lon [Float] Longitude coordinate
  # @return [Hash] Forecast data with:
  #   - :success [Boolean] Whether the request was successful
  #   - :forecast [Array<Hash>] Array of forecast data points
  #   - :error [String] Error message (if unsuccessful)
  def fetch_forecast(lat:, lon:)
    return error_response("Latitude and longitude are required") if lat.blank? || lon.blank?

    response = make_forecast_request(lat, lon)
    return handle_api_error(response) unless response.success?

    {
      success: true,
      forecast: parse_forecast_data(response.parsed_response)
    }
  rescue StandardError => e
    Rails.logger.error("Forecast API error: #{e.message}")
    error_response("An error occurred while fetching forecast data: #{e.message}")
  end

  private

  # Makes the HTTP request to the current weather endpoint
  #
  # @param lat [Float] Latitude coordinate
  # @param lon [Float] Longitude coordinate
  # @return [HTTParty::Response] The API response
  def make_weather_request(lat, lon)
    self.class.get("/data/2.5/weather", query: {
      lat: lat,
      lon: lon,
      units: UNITS,
      appid: @api_key
    })
  end

  # Makes the HTTP request to the forecast endpoint
  #
  # @param lat [Float] Latitude coordinate
  # @param lon [Float] Longitude coordinate
  # @return [HTTParty::Response] The API response
  def make_forecast_request(lat, lon)
    self.class.get("/data/2.5/forecast", query: {
      lat: lat,
      lon: lon,
      units: UNITS,
      appid: @api_key
    })
  end

  # Transforms raw weather API response into our app's format
  #
  # @param data [Hash] Raw API response data
  # @return [Hash] Parsed and structured weather data
  def parse_weather_data(data)
    {
      success: true,
      temperature: data.dig("main", "temp")&.round(1),
      feels_like: data.dig("main", "feels_like")&.round(1),
      high_temp: data.dig("main", "temp_max")&.round(1),
      low_temp: data.dig("main", "temp_min")&.round(1),
      conditions: data.dig("weather", 0, "description")&.titleize,
      humidity: data.dig("main", "humidity"),
      wind_speed: data.dig("wind", "speed"),
      pressure: data.dig("main", "pressure"),
      visibility: data.dig("visibility"),
      icon: data.dig("weather", 0, "icon"),
      sunrise: data.dig("sys", "sunrise"),
      sunset: data.dig("sys", "sunset"),
      raw_data: data
    }
  end

  # Transforms raw forecast API response into a clean array of forecast points
  #
  # Takes the messy API response and pulls out just what we need for each
  # forecast period - temp, conditions, humidity, etc.
  #
  # @param data [Hash] Raw API forecast response data
  # @return [Array<Hash>] Array of parsed forecast data points
  def parse_forecast_data(data)
    return [] unless data["list"].is_a?(Array)

    data["list"].map { |forecast| parse_single_forecast(forecast) }
  end

  # Parses a single forecast data point
  #
  # @param forecast [Hash] Single forecast entry from the API
  # @return [Hash] Parsed forecast data point
  def parse_single_forecast(forecast)
    timestamp = Time.at(forecast["dt"])
    
    {
      datetime: timestamp,
      date: timestamp.strftime("%Y-%m-%d"),
      time: timestamp.strftime("%I:%M %p"),
      temperature: forecast.dig("main", "temp")&.round(1),
      feels_like: forecast.dig("main", "feels_like")&.round(1),
      temp_min: forecast.dig("main", "temp_min")&.round(1),
      temp_max: forecast.dig("main", "temp_max")&.round(1),
      conditions: forecast.dig("weather", 0, "description")&.titleize,
      icon: forecast.dig("weather", 0, "icon"),
      humidity: forecast.dig("main", "humidity"),
      wind_speed: forecast.dig("wind", "speed"),
      pop: (forecast["pop"] * 100).round # Probability of precipitation
    }
  end

  # Maps HTTP status codes to user-friendly error messages
  #
  # @param response [HTTParty::Response] The API response
  # @return [Hash] Error hash with details
  def handle_api_error(response)
    message = case response.code
              when 401 then "Invalid API key"
              when 404 then "Weather data not found for the specified location"
              when 429 then "API rate limit exceeded. Please try again later."
              else "API request failed with status #{response.code}"
              end

    error_response(message)
  end

  # Builds an error response hash
  #
  # @param message [String] The error message
  # @return [Hash] Error response
  def error_response(message)
    { success: false, error: message }
  end
end
