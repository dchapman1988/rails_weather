# frozen_string_literal: true

require 'rails_helper'

# Test suite for the WeatherForecastService.
#
# This spec validates the orchestration service including:
# - Complete forecast workflow
# - Cache checking and storage
# - Service coordination
# - Error handling
#
# @see WeatherForecastService
RSpec.describe WeatherForecastService do
  let(:geocoding_service) { instance_spy(GeocodingService) }
  let(:weather_api_service) { instance_spy(WeatherApiService) }
  let(:service) do
    described_class.new(
      geocoding_service: geocoding_service,
      weather_api_service: weather_api_service
    )
  end

  let(:geocode_result) do
    {
      success: true,
      lat: 40.7128,
      lon: -74.0060,
      zip: '10001',
      location: 'New York, US'
    }
  end

  let(:weather_result) do
    {
      success: true,
      temperature: 72.5,
      feels_like: 70.0,
      high_temp: 75.0,
      low_temp: 68.0,
      conditions: 'Clear Sky',
      humidity: 65,
      wind_speed: 5.2,
      pressure: 1013,
      visibility: 10000,
      icon: '01d',
      sunrise: 1697540400,
      sunset: 1697581200
    }
  end

  describe '#get_forecast' do
    context 'with blank address' do
      it 'returns error' do
        result = service.get_forecast('')

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Address is required')
      end

      it 'returns error for nil address' do
        result = service.get_forecast(nil)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Address is required')
      end
    end

    context 'with valid address and no cache' do
      before do
        allow(geocoding_service).to receive(:geocode).with('New York, NY').and_return(geocode_result)
        allow(weather_api_service).to receive(:fetch_weather)
          .with(lat: 40.7128, lon: -74.0060)
          .and_return(weather_result)
      end

      it 'geocodes the address' do
        service.get_forecast('New York, NY')

        expect(geocoding_service).to have_received(:geocode).with('New York, NY')
      end

      it 'fetches weather data' do
        service.get_forecast('New York, NY')

        expect(weather_api_service).to have_received(:fetch_weather)
          .with(lat: 40.7128, lon: -74.0060)
      end

      it 'returns successful result with weather data' do
        result = service.get_forecast('New York, NY')

        expect(result[:success]).to be true
        expect(result[:from_cache]).to be false
        expect(result[:weather]).to be_a(Hash)
        expect(result[:weather][:temperature]).to eq(72.5)
        expect(result[:location]).to eq('New York, US')
        expect(result[:zip_code]).to eq('10001')
      end

      it 'caches the weather data' do
        expect {
          service.get_forecast('New York, NY')
        }.to change(WeatherCache, :count).by(1)

        cached = WeatherCache.last
        expect(cached.zip_code).to eq('10001')
        expect(cached.temperature).to eq(72.5)
        expect(cached.location).to eq('New York, US')
      end
    end

    context 'with valid cached data' do
      let!(:cached_weather) do
        WeatherCache.create!(
          zip_code: '10001',
          location: 'New York, US',
          temperature: 70.0,
          high_temp: 73.0,
          low_temp: 66.0,
          conditions: 'Cloudy',
          cached_at: 10.minutes.ago,
          data_hash: 'test_hash_123',
          forecast_data: {
            humidity: 60,
            wind_speed: 4.5,
            feels_like: 68.0,
            icon: '02d'
          }
        )
      end

      it 'returns cached data without making API calls' do
        result = service.get_forecast('10001')

        expect(result[:success]).to be true
        expect(result[:from_cache]).to be true
        expect(result[:weather][:temperature]).to eq(70.0)
        expect(result[:cached_at]).to match(/Cached \d+ minutes? ago/)

        # Should not call external services
        expect(geocoding_service).not_to have_received(:geocode)
        expect(weather_api_service).not_to have_received(:fetch_weather)
      end

      it 'includes cache status' do
        result = service.get_forecast('10001')

        expect(result[:cached_at]).to be_present
        expect(result[:cached_at]).to include('Cached')
      end
    end

    context 'with expired cache' do
      let!(:expired_cache) do
        WeatherCache.create!(
          zip_code: '10001',
          location: 'New York, US',
          temperature: 70.0,
          high_temp: 73.0,
          low_temp: 66.0,
          conditions: 'Cloudy',
          cached_at: 45.minutes.ago,
          data_hash: 'test_hash_123'
        )
      end

      before do
        allow(geocoding_service).to receive(:geocode).with('10001').and_return(geocode_result)
        allow(weather_api_service).to receive(:fetch_weather)
          .with(lat: 40.7128, lon: -74.0060)
          .and_return(weather_result)
      end

      it 'fetches fresh data from API' do
        result = service.get_forecast('10001')

        expect(result[:success]).to be true
        expect(result[:from_cache]).to be false
        expect(result[:weather][:temperature]).to eq(72.5) # New data

        expect(geocoding_service).to have_received(:geocode).with('10001')
        expect(weather_api_service).to have_received(:fetch_weather)
      end

      it 'creates new cache entry' do
        expect {
          service.get_forecast('10001')
        }.to change(WeatherCache, :count).by(1)
      end
    end

    context 'with extended forecast request' do
      let(:forecast_result) do
        {
          success: true,
          forecast: [
            {
              datetime: Time.current,
              date: Date.today.to_s,
              time: '12:00 PM',
              temperature: 75.0,
              conditions: 'Clear',
              humidity: 60,
              pop: 10
            }
          ]
        }
      end

      before do
        allow(geocoding_service).to receive(:geocode).with('New York, NY').and_return(geocode_result)
        allow(weather_api_service).to receive(:fetch_weather)
          .with(lat: 40.7128, lon: -74.0060)
          .and_return(weather_result)
        allow(weather_api_service).to receive(:fetch_forecast)
          .with(lat: 40.7128, lon: -74.0060)
          .and_return(forecast_result)
      end

      it 'fetches extended forecast when requested' do
        result = service.get_forecast('New York, NY', include_forecast: true)

        expect(result[:forecast]).to be_an(Array)
        expect(result[:forecast]).not_to be_empty
        expect(weather_api_service).to have_received(:fetch_forecast)
      end

      it 'does not fetch forecast when not requested' do
        result = service.get_forecast('New York, NY', include_forecast: false)

        expect(result[:forecast]).to be_nil
        expect(weather_api_service).not_to have_received(:fetch_forecast)
      end
    end

    context 'when geocoding fails' do
      before do
        allow(geocoding_service).to receive(:geocode)
          .with('InvalidLocation123')
          .and_return({ success: false, error: 'Location not found' })
      end

      it 'returns the geocoding error' do
        result = service.get_forecast('InvalidLocation123')

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Location not found')
      end

      it 'does not attempt to fetch weather' do
        service.get_forecast('InvalidLocation123')

        expect(weather_api_service).not_to have_received(:fetch_weather)
      end
    end

    context 'when weather API fails' do
      before do
        allow(geocoding_service).to receive(:geocode).with('New York, NY').and_return(geocode_result)
        allow(weather_api_service).to receive(:fetch_weather)
          .with(lat: 40.7128, lon: -74.0060)
          .and_return({ success: false, error: 'API error' })
      end

      it 'returns the API error' do
        result = service.get_forecast('New York, NY')

        expect(result[:success]).to be false
        expect(result[:error]).to eq('API error')
      end

      it 'does not create cache entry' do
        expect {
          service.get_forecast('New York, NY')
        }.not_to change(WeatherCache, :count)
      end
    end

    context 'when address contains zip code' do
      before do
        allow(weather_api_service).to receive(:fetch_weather)
          .with(lat: 40.7128, lon: -74.0060)
          .and_return(weather_result)
      end

      it 'checks cache before geocoding' do
        # Create cache for zip code
        WeatherCache.create!(
          zip_code: '10001',
          location: 'New York, US',
          temperature: 70.0,
          high_temp: 73.0,
          low_temp: 66.0,
          conditions: 'Cloudy',
          cached_at: 10.minutes.ago,
          data_hash: 'test_hash_123'
        )

        result = service.get_forecast('New York, NY 10001')

        expect(result[:from_cache]).to be true
        expect(geocoding_service).not_to have_received(:geocode)
      end
    end
  end
end
