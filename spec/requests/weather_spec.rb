# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Weather", type: :request do
  describe "GET /weather" do
    it "returns http success" do
      get weather_path
      expect(response).to have_http_status(:success)
    end

    it "displays the weather form" do
      get weather_path
      expect(response.body).to include("Enter Address, City, or Zip Code")
      expect(response.body).to include("Get Weather")
    end

    it "displays the forecast checkbox" do
      get weather_path
      expect(response.body).to include("Include 5-day extended forecast")
    end
  end

  describe "POST /weather/forecast" do
    let(:valid_address) { "New York, NY 10001" }
    let(:invalid_address) { "" }

    context "with valid address and successful forecast" do
      let(:service_double) { instance_double(WeatherForecastService) }

      before do
        allow(WeatherForecastService).to receive(:new).and_return(service_double)
        
        allow(service_double).to receive(:get_forecast).with(valid_address, include_forecast: true).and_return({
          success: true,
          from_cache: false,
          weather: {
            temperature: 72.5,
            high_temp: 75.0,
            low_temp: 68.0,
            conditions: "Clear",
            humidity: 65,
            wind_speed: 5.5,
            feels_like: 70.0,
            icon: "01d"
          },
          forecast: [
            {
              date: "2025-10-18",
              high_temp: 76.0,
              low_temp: 65.0,
              conditions: "Sunny",
              humidity: 60,
              pop: 10,
              icon: "01d"
            }
          ],
          location: "New York, US",
          zip_code: "10001"
        })
      end

      it "returns http success with turbo stream format" do
        post weather_forecast_path, params: { address: valid_address, include_forecast: "1" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response).to have_http_status(:success)
        expect(response.content_type).to include("turbo-stream")
      end

      it "calls the weather service with correct parameters" do
        expect(service_double).to receive(:get_forecast).with(valid_address, include_forecast: true)
        post weather_forecast_path, params: { address: valid_address, include_forecast: "1" }
      end

      it "returns http success with html format" do
        post weather_forecast_path, params: { address: valid_address, include_forecast: "1" }
        expect(response).to have_http_status(:success)
      end
    end

    context "with invalid address" do
      it "returns http success and renders index" do
        post weather_forecast_path, params: { address: invalid_address }
        expect(response).to have_http_status(:success)
      end
    end

    context "with service error" do
      let(:service_double) { instance_double(WeatherForecastService) }

      before do
        allow(WeatherForecastService).to receive(:new).and_return(service_double)
        
        allow(service_double).to receive(:get_forecast).and_return({
          success: false,
          error: "Unable to find location for the provided address"
        })
      end

      it "returns http success and handles error gracefully" do
        post weather_forecast_path, params: { address: "Invalid Location 99999" }
        expect(response).to have_http_status(:success)
      end

      it "calls the weather service" do
        expect(service_double).to receive(:get_forecast)
        post weather_forecast_path, params: { address: "Invalid Location 99999" }
      end
    end

    context "with cached data" do
      let(:service_double) { instance_double(WeatherForecastService) }

      before do
        allow(WeatherForecastService).to receive(:new).and_return(service_double)
        
        allow(service_double).to receive(:get_forecast).and_return({
          success: true,
          from_cache: true,
          cached_at: "Cached 5 minutes ago",
          weather: {
            temperature: 70.0,
            high_temp: 73.0,
            low_temp: 66.0,
            conditions: "Cloudy",
            humidity: 60,
            wind_speed: 4.5,
            feels_like: 68.0,
            icon: "04d"
          },
          forecast: [],
          location: "New York, US",
          zip_code: "10001"
        })
      end

      it "returns http success with cached data" do
        post weather_forecast_path, params: { address: valid_address }
        expect(response).to have_http_status(:success)
      end

      it "calls the weather service which returns cached data" do
        expect(service_double).to receive(:get_forecast).and_return(hash_including(from_cache: true))
        post weather_forecast_path, params: { address: valid_address }
      end
    end

    context "with forecast disabled" do
      let(:service_double) { instance_double(WeatherForecastService) }

      before do
        allow(WeatherForecastService).to receive(:new).and_return(service_double)
        
        allow(service_double).to receive(:get_forecast).with(valid_address, include_forecast: false).and_return({
          success: true,
          from_cache: false,
          weather: {
            temperature: 72.5,
            high_temp: 75.0,
            low_temp: 68.0,
            conditions: "Clear",
            humidity: 65,
            wind_speed: 5.5
          },
          forecast: nil,
          location: "New York, US",
          zip_code: "10001"
        })
      end

      it "calls service without forecast" do
        expect(service_double).to receive(:get_forecast)
          .with(valid_address, include_forecast: false)

        post weather_forecast_path, params: { address: valid_address, include_forecast: "0" }
      end

      it "does not display forecast section" do
        post weather_forecast_path, params: { address: valid_address, include_forecast: "0" }
        expect(response.body).not_to include("5-Day Forecast")
      end
    end
  end

  describe "GET /" do
    it "returns http success" do
      get root_path
      expect(response).to have_http_status(:success)
    end

    it "displays the weather application" do
      get root_path
      expect(response.body).to include("Weather Forecast")
      expect(response.body).to include("Enter Address, City, or Zip Code")
    end
  end
end

