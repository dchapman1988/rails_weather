class CreateWeatherCaches < ActiveRecord::Migration[8.0]
  def change
    create_table :weather_caches do |t|
      t.string :zip_code, null: false
      t.string :location
      t.decimal :temperature, precision: 5, scale: 2
      t.decimal :high_temp, precision: 5, scale: 2
      t.decimal :low_temp, precision: 5, scale: 2
      t.string :conditions
      t.datetime :cached_at, null: false
      t.json :forecast_data

      t.timestamps
    end

    add_index :weather_caches, :zip_code
    add_index :weather_caches, :cached_at
  end
end
