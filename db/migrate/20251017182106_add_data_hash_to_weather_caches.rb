class AddDataHashToWeatherCaches < ActiveRecord::Migration[8.0]
  def up
    add_column :weather_caches, :data_hash, :string
    # Set a default hash for existing records
    WeatherCache.update_all(data_hash: 'legacy')
    change_column_null :weather_caches, :data_hash, false
    add_index :weather_caches, :data_hash
  end

  def down
    remove_index :weather_caches, :data_hash
    remove_column :weather_caches, :data_hash
  end
end
