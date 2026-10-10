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

ActiveRecord::Schema[8.1].define(version: 2026_10_10_170100) do
  create_table "quote_lines", force: :cascade do |t|
    t.integer "quote_id", null: false
    t.integer "position", null: false
    t.string "description"
    t.text "original_text"
    t.json "spec"
    t.decimal "quantity", precision: 18, scale: 4
    t.string "quantity_unit"
    t.string "catalog_sku"
    t.decimal "unit_price", precision: 18, scale: 4
    t.string "price_source"
    t.string "state", default: "needs_buyer", null: false
    t.text "clarification_question"
    t.text "notes"
    t.json "evidence"
    t.json "compliance"
    t.json "benchmark"
    t.json "unresolved_fields"
    t.json "edited_fields"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["quote_id", "position"], name: "index_quote_lines_on_quote_id_and_position", unique: true
    t.index ["quote_id"], name: "index_quote_lines_on_quote_id"
  end

  create_table "quotes", force: :cascade do |t|
    t.string "title", null: false
    t.string "buyer_name"
    t.text "source_text"
    t.string "original_filename"
    t.binary "source_bytes", limit: 10485760
    t.string "workspace_token", null: false
    t.boolean "sample_data", default: false, null: false
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_token", "created_at"], name: "index_quotes_on_workspace_token_and_created_at"
  end

  add_foreign_key "quote_lines", "quotes", on_delete: :cascade
end
