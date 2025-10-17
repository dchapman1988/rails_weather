# frozen_string_literal: true

# Handles weather forecast requests from users
#
# Users submit an address, and we fetch and display current weather conditions
# plus an optional extended forecast. All the heavy lifting happens in
# WeatherForecastService - this controller just coordinates between the user
# and that service.
class WeatherController < ApplicationController
  # Shows the weather search form
  #
  # @return [void]
  def index
    # That's it - just render the view
  end

  # Fetches and displays weather for the submitted address
  #
  # Users can optionally disable the extended forecast by passing
  # include_forecast=0 in the params.
  #
  # @param params [ActionController::Parameters] Must include address
  # @return [void] Renders turbo stream or HTML response
  def forecast
    return handle_missing_address if params[:address].blank?

    fetch_weather_data
    render_forecast_response
  rescue StandardError => e
    handle_error(e)
  end

  private

  # Handles the case when no address was provided
  #
  # @return [void]
  def handle_missing_address
    @error = "Please enter an address to search for weather"
    render_forecast_response
  end

  # Calls the weather service and assigns results to instance variables
  #
  # @return [void]
  def fetch_weather_data
    result = WeatherForecastService.new.get_forecast(
      params[:address],
      include_forecast: include_extended_forecast?
    )

    if result[:success]
      assign_weather_data(result)
    else
      @error = result[:error]
    end
  end

  # Unpacks the weather data hash into instance variables for the view
  #
  # @param result [Hash] The successful result from the weather service
  # @return [void]
  def assign_weather_data(result)
    @weather = result[:weather]
    @forecast = result[:forecast]
    @location = result[:location]
    @zip_code = result[:zip_code]
    @from_cache = result[:from_cache]
    @cached_at = result[:cached_at]
  end

  # Checks whether the user wants the extended forecast included
  #
  # @return [Boolean] False only if explicitly set to "0", otherwise true
  def include_extended_forecast?
    params[:include_forecast] != "0"
  end

  # Logs the error and sets a user-friendly error message
  #
  # @param error [StandardError] The exception that was raised
  # @return [void]
  def handle_error(error)
    Rails.logger.error("Weather forecast error: #{error.message}\n#{error.backtrace.join("\n")}")
    @error = "An unexpected error occurred. Please try again."
    render_forecast_response
  end

  # Renders either a Turbo Stream update or falls back to the index view
  #
  # @return [void]
  def render_forecast_response
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "forecast_results",
          partial: "weather/forecast_results"
        )
      end
      format.html { render :index }
    end
  end
end
