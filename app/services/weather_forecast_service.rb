# frozen_string_literal: true

# Orchestrates the complete weather forecast workflow
#
# This is the main service that ties everything together - it coordinates between
# geocoding, cache checking, API calls, and cache storage. Controllers just call
# this service and get back everything they need in one shot.
class WeatherForecastService
  CACHE_DURATION_MINUTES = 30

  # Initializes the service with its dependencies
  #
  # We use dependency injection here so it's easy to swap in mocks during testing.
  #
  # @param geocoding_service [GeocodingService] Service for geocoding addresses
  # @param weather_api_service [WeatherApiService] Service for fetching weather data
  def initialize(geocoding_service: GeocodingService.new, weather_api_service: WeatherApiService.new)
    @geocoding_service = geocoding_service
    @weather_api_service = weather_api_service
  end

  # Gets weather forecast for an address - the main entry point
  #
  # This method handles the whole workflow: checks cache first (fast!), falls back
  # to geocoding and API calls if needed, then stores the results for next time.
  #
  # @param address [String] The address to get weather for (city, state, zip, or full address)
  # @param include_forecast [Boolean] Whether to include extended forecast data
  # @return [Hash] Weather data with:
  #   - :success [Boolean] Whether the operation was successful
  #   - :from_cache [Boolean] Whether the data came from cache
  #   - :cached_at [String] Human-readable cache timestamp (if from cache)
  #   - :weather [Hash] Current weather data
  #   - :forecast [Array<Hash>] Extended forecast data (if requested)
  #   - :location [String] Formatted location name
  #   - :zip_code [String] Zip code for the location
  #   - :error [String] Error message (if unsuccessful)
  def get_forecast(address, include_forecast: false)
    return error_response("Address is required") if address.blank?

    # Quick win: if there's a zip in the address, try cache immediately
    if (zip_code = extract_zip_code(address))
      cached = try_cache(zip_code, include_forecast)
      return cached if cached
    end

    # Cache miss or no zip - geocode the address
    geocode_result = @geocoding_service.geocode(address)
    return geocode_result unless geocode_result[:success]

    lat = geocode_result[:lat]
    lon = geocode_result[:lon]
    zip_code ||= geocode_result[:zip]
    location = geocode_result[:location]

    # Try cache again now that we have a zip code from geocoding
    if zip_code
      cached = try_cache(zip_code, include_forecast, location: location)
      return cached if cached
    end

    # No cache hit - fetch fresh data from the API
    fetch_and_cache_weather(lat, lon, zip_code, location, include_forecast)
  rescue StandardError => e
    Rails.logger.error("WeatherForecastService error: #{e.message}\n#{e.backtrace.join("\n")}")
    error_response("An unexpected error occurred: #{e.message}")
  end

  private

  # Pulls out a 5-digit zip code from an address string
  #
  # @param address [String] The address to search
  # @return [String, nil] The extracted zip code or nil
  def extract_zip_code(address)
    address.match(/\b\d{5}\b/)&.to_s
  end

  # Attempts to retrieve weather from cache
  #
  # Returns nil if cache miss or if we need forecast but don't have it cached.
  #
  # @param zip_code [String] The zip code to check
  # @param include_forecast [Boolean] Whether forecast is required
  # @param location [String, nil] Optional location to merge into cached result
  # @return [Hash, nil] Cached weather data or nil if not usable
  def try_cache(zip_code, include_forecast, location: nil)
    cached = WeatherCache.fetch_valid_cache(zip_code)
    return nil unless cached

    # If we need forecast but cache doesn't have it, skip cache
    if include_forecast && cached.forecast_data&.dig("forecast").nil?
      Rails.logger.info("Cache exists but missing forecast data, fetching fresh")
      return nil
    end

    build_cached_response(cached, location)
  end

  # Builds a response hash from cached weather data
  #
  # @param cached [WeatherCache] The cached weather record
  # @param location_override [String, nil] Optional location to override cached location
  # @return [Hash] Formatted cached weather response
  def build_cached_response(cached, location_override = nil)
    {
      success: true,
      from_cache: true,
      cached_at: cached.cache_status,
      weather: {
        temperature: cached.temperature,
        high_temp: cached.high_temp,
        low_temp: cached.low_temp,
        conditions: cached.conditions,
        humidity: cached.forecast_data&.dig("humidity"),
        wind_speed: cached.forecast_data&.dig("wind_speed"),
        feels_like: cached.forecast_data&.dig("feels_like"),
        icon: cached.forecast_data&.dig("icon")
      },
      forecast: normalize_forecast_data(cached.forecast_data&.dig("forecast")),
      location: location_override || cached.location,
      zip_code: cached.zip_code
    }
  end

  # Fetches weather from API and caches the results
  #
  # @param lat [Float] Latitude
  # @param lon [Float] Longitude
  # @param zip_code [String, nil] Zip code for caching
  # @param location [String] Formatted location name
  # @param include_forecast [Boolean] Whether to fetch extended forecast
  # @return [Hash] Fresh weather data response
  def fetch_and_cache_weather(lat, lon, zip_code, location, include_forecast)
    weather_result = @weather_api_service.fetch_weather(lat: lat, lon: lon)
    return weather_result unless weather_result[:success]

    forecast_data = fetch_forecast_if_needed(lat, lon, include_forecast)

    # Store in cache if we have a zip code
    cache_weather_data(zip_code, location, weather_result, forecast_data) if zip_code

    build_fresh_response(weather_result, forecast_data, location, zip_code)
  end

  # Fetches extended forecast if requested
  #
  # @param lat [Float] Latitude
  # @param lon [Float] Longitude
  # @param include_forecast [Boolean] Whether to fetch forecast
  # @return [Array, nil] Forecast data or nil
  def fetch_forecast_if_needed(lat, lon, include_forecast)
    return nil unless include_forecast

    forecast_result = @weather_api_service.fetch_forecast(lat: lat, lon: lon)
    forecast_result[:success] ? forecast_result[:forecast] : nil
  end

  # Builds a response hash from fresh API data
  #
  # @param weather_result [Hash] Weather data from API
  # @param forecast_data [Array, nil] Forecast data from API
  # @param location [String] Formatted location name
  # @param zip_code [String, nil] Zip code
  # @return [Hash] Formatted fresh weather response
  def build_fresh_response(weather_result, forecast_data, location, zip_code)
    {
      success: true,
      from_cache: false,
      weather: extract_weather_data(weather_result),
      forecast: forecast_data,
      location: location,
      zip_code: zip_code
    }
  end

  # Stores weather data in the cache
  #
  # If caching fails, we log it but don't fail the request - we still got the
  # weather data successfully, just couldn't cache it for later.
  #
  # @param zip_code [String] The zip code for the location
  # @param location [String] The formatted location name
  # @param weather_data [Hash] The weather data to cache
  # @param forecast_data [Array, nil] The extended forecast data (optional)
  # @return [WeatherCache, nil] The cached record or nil if caching failed
  def cache_weather_data(zip_code, location, weather_data, forecast_data = nil)
    combined_data = weather_data.merge(forecast: forecast_data)
    data_hash = WeatherCache.generate_data_hash(combined_data, include_forecast: forecast_data.present?)

    WeatherCache.create!(
      zip_code: zip_code,
      location: location,
      temperature: weather_data[:temperature],
      high_temp: weather_data[:high_temp],
      low_temp: weather_data[:low_temp],
      conditions: weather_data[:conditions],
      cached_at: Time.current,
      data_hash: data_hash,
      forecast_data: build_forecast_data_hash(weather_data, forecast_data)
    )
  rescue StandardError => e
    Rails.logger.error("Failed to cache weather data: #{e.message}")
    nil
  end

  # Builds the forecast_data hash for storage
  #
  # @param weather_data [Hash] The weather data
  # @param forecast_data [Array, nil] The forecast data
  # @return [Hash] Combined data for the forecast_data column
  def build_forecast_data_hash(weather_data, forecast_data)
    {
      humidity: weather_data[:humidity],
      wind_speed: weather_data[:wind_speed],
      feels_like: weather_data[:feels_like],
      pressure: weather_data[:pressure],
      visibility: weather_data[:visibility],
      icon: weather_data[:icon],
      sunrise: weather_data[:sunrise],
      sunset: weather_data[:sunset],
      forecast: forecast_data
    }
  end

  # Pulls out just the weather fields we want to return
  #
  # @param weather_data [Hash] The full weather data from the API
  # @return [Hash] Cleaned weather data for response
  def extract_weather_data(weather_data)
    {
      temperature: weather_data[:temperature],
      feels_like: weather_data[:feels_like],
      high_temp: weather_data[:high_temp],
      low_temp: weather_data[:low_temp],
      conditions: weather_data[:conditions],
      humidity: weather_data[:humidity],
      wind_speed: weather_data[:wind_speed],
      pressure: weather_data[:pressure],
      visibility: weather_data[:visibility],
      icon: weather_data[:icon],
      sunrise: weather_data[:sunrise],
      sunset: weather_data[:sunset]
    }
  end

  # Normalizes forecast data to use consistent symbol keys
  #
  # Cached data comes back with string keys from JSON, but API data uses symbols.
  # This makes everything consistent.
  #
  # @param forecast_data [Array, nil] The forecast data to normalize
  # @return [Array, nil] Normalized forecast data with symbol keys
  def normalize_forecast_data(forecast_data)
    return nil unless forecast_data.is_a?(Array)

    forecast_data.map do |forecast|
      forecast.is_a?(Hash) ? forecast.transform_keys(&:to_sym) : forecast
    end
  end

  # Builds an error response hash
  #
  # @param message [String] The error message
  # @return [Hash] Error response
  def error_response(message)
    { success: false, error: message }
  end
end

