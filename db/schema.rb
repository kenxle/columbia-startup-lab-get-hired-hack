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

ActiveRecord::Schema[8.1].define(version: 2026_10_10_184500) do
  create_table "client_terms", force: :cascade do |t|
    t.integer "client_id", null: false
    t.string "term", null: false
    t.json "meaning", null: false
    t.string "source", null: false
    t.integer "times_confirmed", default: 1, null: false
    t.integer "last_match_request_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id", "term"], name: "index_client_terms_on_client_id_and_term", unique: true
    t.index ["client_id"], name: "index_client_terms_on_client_id"
  end

  create_table "clients", force: :cascade do |t|
    t.string "name", null: false
    t.string "workspace_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_token", "name"], name: "index_clients_on_workspace_token_and_name", unique: true
  end

  create_table "match_requests", force: :cascade do |t|
    t.integer "client_id", null: false
    t.text "description", null: false
    t.string "outcome", null: false
    t.json "result", null: false
    t.json "approved_part_numbers"
    t.decimal "quantity", precision: 18, scale: 4
    t.integer "quote_id"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_match_requests_on_client_id"
  end

  create_table "processing_runs", force: :cascade do |t|
    t.integer "quote_id", null: false
    t.string "status", default: "queued", null: false
    t.string "requested_revision", null: false
    t.string "source_revision", null: false
    t.binary "source_content", limit: 10485760
    t.string "source_type"
    t.string "source_filename"
    t.text "error_message"
    t.json "warnings"
    t.datetime "queued_at", null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["quote_id", "status"], name: "index_processing_runs_on_quote_id_and_status"
    t.index ["quote_id"], name: "index_processing_runs_on_quote_id"
  end

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
    t.string "line_id"
    t.json "processing"
    t.string "lead_time"
    t.string "lead_time_source"
    t.index ["quote_id", "line_id"], name: "index_quote_lines_on_quote_id_and_line_id", unique: true
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
    t.json "processing_revision"
    t.json "processing_source"
    t.json "processing_warnings", default: [], null: false
    t.index ["workspace_token", "created_at"], name: "index_quotes_on_workspace_token_and_created_at"
  end

  add_foreign_key "client_terms", "clients", on_delete: :cascade
  add_foreign_key "match_requests", "clients", on_delete: :cascade
  add_foreign_key "processing_runs", "quotes", on_delete: :cascade
  add_foreign_key "quote_lines", "quotes", on_delete: :cascade
end
