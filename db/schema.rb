# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_10_17_182106) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "weather_caches", force: :cascade do |t|
    t.string "zip_code", null: false
    t.string "location"
    t.decimal "temperature", precision: 5, scale: 2
    t.decimal "high_temp", precision: 5, scale: 2
    t.decimal "low_temp", precision: 5, scale: 2
    t.string "conditions"
    t.datetime "cached_at", null: false
    t.json "forecast_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "data_hash", null: false
    t.index ["cached_at"], name: "index_weather_caches_on_cached_at"
    t.index ["data_hash"], name: "index_weather_caches_on_data_hash"
    t.index ["zip_code"], name: "index_weather_caches_on_zip_code"
  end
end
