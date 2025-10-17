# frozen_string_literal: true

require 'rails_helper'

# Test suite for the WeatherCache model.
#
# This spec validates all aspects of the WeatherCache model including:
# - Database validations
# - Scopes for querying valid cache entries
# - Class methods for cache retrieval
# - Instance methods for cache status
#
# @see WeatherCache
RSpec.describe WeatherCache, type: :model do
  describe 'validations' do
  let(:valid_attributes) do
    {
      zip_code: '10001',
      location: 'New York, US',
      temperature: 72.5,
      high_temp: 75.0,
      low_temp: 68.0,
      conditions: 'Clear',
      cached_at: Time.current,
      data_hash: 'test_hash_123',
      forecast_data: { humidity: 65 }
    }
  end

    it 'is valid with valid attributes' do
      weather_cache = WeatherCache.new(valid_attributes)
      expect(weather_cache).to be_valid
    end

    describe 'zip_code' do
      it 'is required' do
        weather_cache = WeatherCache.new(valid_attributes.except(:zip_code))
        expect(weather_cache).not_to be_valid
        expect(weather_cache.errors[:zip_code]).to include("can't be blank")
      end

      it 'must be a 5-digit code' do
        weather_cache = WeatherCache.new(valid_attributes.merge(zip_code: '123'))
        expect(weather_cache).not_to be_valid
        expect(weather_cache.errors[:zip_code]).to include('must be a 5-digit zip code')
      end

      it 'accepts valid 5-digit zip codes' do
        weather_cache = WeatherCache.new(valid_attributes.merge(zip_code: '90210'))
        expect(weather_cache).to be_valid
      end
    end

    describe 'cached_at' do
      it 'is required' do
        weather_cache = WeatherCache.new(valid_attributes.except(:cached_at))
        expect(weather_cache).not_to be_valid
        expect(weather_cache.errors[:cached_at]).to include("can't be blank")
      end
    end

    describe 'temperature fields' do
      it 'validates temperature is numeric' do
        weather_cache = WeatherCache.new(valid_attributes.merge(temperature: 'invalid'))
        expect(weather_cache).not_to be_valid
      end

      it 'validates high_temp is numeric' do
        weather_cache = WeatherCache.new(valid_attributes.merge(high_temp: 'invalid'))
        expect(weather_cache).not_to be_valid
      end

      it 'validates low_temp is numeric' do
        weather_cache = WeatherCache.new(valid_attributes.merge(low_temp: 'invalid'))
        expect(weather_cache).not_to be_valid
      end

      it 'allows nil values for temperature fields' do
        weather_cache = WeatherCache.new(
          valid_attributes.merge(
            temperature: nil,
            high_temp: nil,
            low_temp: nil
          )
        )
        expect(weather_cache).to be_valid
      end
    end
  end

  describe 'scopes' do
    describe '.valid_cache' do
      let!(:recent_cache) do
        WeatherCache.create!(
          zip_code: '10001',
          location: 'New York, US',
          temperature: 72.5,
          high_temp: 75.0,
          low_temp: 68.0,
          cached_at: 10.minutes.ago,
          data_hash: 'test_hash_123'
        )
      end

      let!(:old_cache) do
        WeatherCache.create!(
          zip_code: '10001',
          location: 'New York, US',
          temperature: 70.0,
          high_temp: 73.0,
          low_temp: 66.0,
          cached_at: 45.minutes.ago,
          data_hash: 'test_hash_123'
        )
      end

      let!(:different_zip) do
        WeatherCache.create!(
          zip_code: '90210',
          location: 'Beverly Hills, US',
          temperature: 85.0,
          high_temp: 88.0,
          low_temp: 78.0,
          cached_at: 5.minutes.ago,
          data_hash: 'test_hash_123'
        )
      end

      it 'returns only caches for the specified zip code' do
        results = WeatherCache.valid_cache('10001')
        expect(results).to include(recent_cache)
        expect(results).not_to include(different_zip)
      end

      it 'returns only caches from the last 30 minutes' do
        results = WeatherCache.valid_cache('10001')
        expect(results).to include(recent_cache)
        expect(results).not_to include(old_cache)
      end

      it 'orders results by cached_at descending' do
        # Create another recent cache for the same zip
        newer_cache = WeatherCache.create!(
          zip_code: '10001',
          location: 'New York, US',
          temperature: 73.0,
          high_temp: 76.0,
          low_temp: 69.0,
          cached_at: 5.minutes.ago,
          data_hash: 'test_hash_123'
        )

        results = WeatherCache.valid_cache('10001').to_a
        expect(results.first).to eq(newer_cache)
        expect(results.second).to eq(recent_cache)
      end
    end
  end

  describe '.fetch_valid_cache' do
    it 'returns the most recent valid cache entry' do
      WeatherCache.create!(
        zip_code: '10001',
        location: 'New York, US',
        temperature: 72.5,
        high_temp: 75.0,
        low_temp: 68.0,
        cached_at: 20.minutes.ago,
        data_hash: 'test_hash_123'
      )

      newer_cache = WeatherCache.create!(
        zip_code: '10001',
        location: 'New York, US',
        temperature: 73.0,
        high_temp: 76.0,
        low_temp: 69.0,
        cached_at: 10.minutes.ago,
        data_hash: 'test_hash_123'
      )

      result = WeatherCache.fetch_valid_cache('10001')
      expect(result).to eq(newer_cache)
    end

    it 'returns nil when no valid cache exists' do
      WeatherCache.create!(
        zip_code: '10001',
        location: 'New York, US',
        temperature: 72.5,
        high_temp: 75.0,
        low_temp: 68.0,
        cached_at: 45.minutes.ago,
        data_hash: 'test_hash_123'
      )

      result = WeatherCache.fetch_valid_cache('10001')
      expect(result).to be_nil
    end

    it 'returns nil for non-existent zip codes' do
      result = WeatherCache.fetch_valid_cache('99999')
      expect(result).to be_nil
    end
  end

  describe '#cache_valid?' do
    it 'returns true for cache less than 30 minutes old' do
      weather_cache = WeatherCache.create!(
        zip_code: '10001',
        location: 'New York, US',
        temperature: 72.5,
        high_temp: 75.0,
        low_temp: 68.0,
        cached_at: 15.minutes.ago,
        data_hash: 'test_hash_123'
      )

      expect(weather_cache.cache_valid?).to be true
    end

    it 'returns false for cache older than 30 minutes' do
      weather_cache = WeatherCache.create!(
        zip_code: '10001',
        location: 'New York, US',
        temperature: 72.5,
        high_temp: 75.0,
        low_temp: 68.0,
        cached_at: 35.minutes.ago,
        data_hash: 'test_hash_123'
      )

      expect(weather_cache.cache_valid?).to be false
    end
  end

  describe '#cache_status' do
    it 'returns "Cached X minutes ago" for valid cache' do
      weather_cache = WeatherCache.create!(
        zip_code: '10001',
        location: 'New York, US',
        temperature: 72.5,
        high_temp: 75.0,
        low_temp: 68.0,
        cached_at: 10.minutes.ago,
        data_hash: 'test_hash_123'
      )

      expect(weather_cache.cache_status).to match(/Cached \d+ minutes? ago/)
    end

    it 'returns "Cache expired" for old cache' do
      weather_cache = WeatherCache.create!(
        zip_code: '10001',
        location: 'New York, US',
        temperature: 72.5,
        high_temp: 75.0,
        low_temp: 68.0,
        cached_at: 45.minutes.ago,
        data_hash: 'test_hash_123'
      )

      expect(weather_cache.cache_status).to eq('Cache expired')
    end

    it 'uses correct pluralization' do
      weather_cache = WeatherCache.create!(
        zip_code: '10001',
        location: 'New York, US',
        temperature: 72.5,
        high_temp: 75.0,
        low_temp: 68.0,
        cached_at: 1.minute.ago,
        data_hash: 'test_hash_123'
      )

      expect(weather_cache.cache_status).to match(/Cached \d+ minute ago/)
    end
  end
end
