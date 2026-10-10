class AddProcessingMetadata < ActiveRecord::Migration[8.1]
  def change
    add_column :quotes, :processing_revision, :json
    add_column :quote_lines, :line_id, :string
    add_column :quote_lines, :processing, :json
    add_index :quote_lines, [:quote_id, :line_id], unique: true
  end
end
