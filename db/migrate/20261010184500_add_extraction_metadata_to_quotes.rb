class AddExtractionMetadataToQuotes < ActiveRecord::Migration[8.1]
  def change
    add_column :quotes, :processing_source, :json
    add_column :quotes, :processing_warnings, :json, default: [], null: false
  end
end
