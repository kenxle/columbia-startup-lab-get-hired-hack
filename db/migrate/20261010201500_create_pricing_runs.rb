class CreatePricingRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :pricing_runs do |t|
      t.references :quote, null: false, foreign_key: { on_delete: :cascade }
      t.string :status, null: false, default: "queued"
      t.string :source_revision, null: false
      t.string :applied_revision
      t.json :applied_line_ids, null: false, default: []
      t.string :source_digest, null: false
      t.json :destination, null: false
      t.string :currency, null: false
      t.date :delivery_by
      t.json :result
      t.text :error_message
      t.datetime :queued_at, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :pricing_runs, [:quote_id, :status]
  end
end
