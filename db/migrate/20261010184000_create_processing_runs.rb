class CreateProcessingRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :processing_runs do |t|
      t.references :quote, null: false, foreign_key: { on_delete: :cascade }
      t.string :status, null: false, default: "queued"
      t.string :requested_revision, null: false
      t.string :source_revision, null: false
      t.binary :source_content, limit: 10.megabytes
      t.string :source_type
      t.string :source_filename
      t.text :error_message
      t.json :warnings
      t.datetime :queued_at, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :processing_runs, [:quote_id, :status]
  end
end
