# frozen_string_literal: true

# Caches weather data to avoid hammering the OpenWeather API
#
# We store weather forecasts by zip code and keep them fresh for 30 minutes.
# This speeds up responses and saves on API costs when multiple users check
# the same location.
class WeatherCache < ApplicationRecord
  CACHE_DURATION = 30.minutes

  # Validations
  validates :zip_code, presence: true, 
                       format: { with: /\A\d{5}\z/, message: "must be a 5-digit zip code" }
  validates :cached_at, presence: true
  validates :data_hash, presence: true
  validates :temperature, :high_temp, :low_temp, numericality: true, allow_nil: true

  # Returns unexpired cache entries for a zip code, optionally matching a data hash
  #
  # @param zip_code [String] The 5-digit zip code to lookup
  # @param data_hash [String, nil] Optional hash to match - only returns cache if data hasn't changed
  # @return [ActiveRecord::Relation]
  scope :valid_cache, ->(zip_code, data_hash = nil) {
    recent_cache = where(zip_code: zip_code)
                     .where(cached_at: CACHE_DURATION.ago..)
                     .order(cached_at: :desc)
    
    data_hash.present? ? recent_cache.where(data_hash: data_hash) : recent_cache
  }

  # Finds unexpired cache for a zip code, optionally matching a specific data hash
  #
  # The data_hash check is useful when you want to know if the weather has
  # actually changed since last time - if the hash matches, nothing's new.
  #
  # @param zip_code [String] The 5-digit zip code to lookup
  # @param data_hash [String, nil] Optional hash of current weather data to compare against
  # @return [WeatherCache, nil] The cached weather data or nil if not found/expired/changed
  def self.fetch_valid_cache(zip_code, data_hash = nil)
    valid_cache(zip_code, data_hash).first
  end

  # Creates a fingerprint of the weather data to detect changes
  #
  # We hash the important bits (temps, conditions, forecast) so we can tell
  # when weather has actually changed vs just re-fetching the same data.
  #
  # @param weather_data [Hash] The current weather data
  # @param include_forecast [Boolean] Whether to include forecast in the hash
  # @return [String] MD5 hash representing the current weather state
  def self.generate_data_hash(weather_data, include_forecast: true)
    key_data = build_hash_key_data(weather_data, include_forecast)
    Digest::MD5.hexdigest(key_data.to_json)
  end

  # Is this cache entry still fresh enough to use?
  #
  # @return [Boolean] True if cached within the last 30 minutes
  def cache_valid?
    cached_at > CACHE_DURATION.ago
  end

  # Human-friendly description of how old this cache is
  #
  # @return [String] Cache status message like "Cached 5 minutes ago"
  def cache_status
    return "Cache expired" unless cache_valid?

    minutes_ago = time_cached_minutes_ago
    "Cached #{minutes_ago} #{'minute'.pluralize(minutes_ago)} ago"
  end

  private

  # Builds the hash key data from weather information
  #
  # @param weather_data [Hash] The weather data to hash
  # @param include_forecast [Boolean] Whether to include forecast data
  # @return [Hash] The key data to be hashed
  def self.build_hash_key_data(weather_data, include_forecast)
    key_data = {
      temp: weather_data[:temperature]&.round(1),
      high: weather_data[:high_temp]&.round(1),
      low: weather_data[:low_temp]&.round(1),
      conditions: weather_data[:conditions]
    }

    key_data[:forecast] = simplified_forecast(weather_data[:forecast]) if include_forecast && weather_data[:forecast]
    
    key_data
  end

  # Simplifies forecast data down to just the essentials for hashing
  #
  # @param forecast_data [Array<Hash>] The full forecast data
  # @return [Array<Hash>] Simplified forecast with just date, temps, and conditions
  def self.simplified_forecast(forecast_data)
    forecast_data.map do |day|
      {
        date: day[:date],
        high: day[:high_temp]&.round(1),
        low: day[:low_temp]&.round(1),
        conditions: day[:conditions]
      }
    end
  end

  # Calculates how many minutes ago this entry was cached
  #
  # @return [Integer] Minutes since cached_at
  def time_cached_minutes_ago
    ((Time.current - cached_at) / 60).round
  end
end
