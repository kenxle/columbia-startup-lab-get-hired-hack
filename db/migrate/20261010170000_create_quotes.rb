class CreateQuotes < ActiveRecord::Migration[8.1]
  def change
    create_table :quotes do |table|
      table.string :title, null: false
      table.string :buyer_name
      table.text :source_text
      table.string :original_filename
      table.binary :source_bytes, limit: 10.megabytes
      table.string :workspace_token, null: false
      table.boolean :sample_data, null: false, default: false
      table.datetime :approved_at
      table.timestamps
    end

    add_index :quotes, [ :workspace_token, :created_at ]
  end
end
