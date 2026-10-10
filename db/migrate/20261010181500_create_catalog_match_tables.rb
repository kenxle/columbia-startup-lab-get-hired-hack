class CreateCatalogMatchTables < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.string :name, null: false
      t.string :workspace_token, null: false
      t.timestamps
    end
    add_index :clients, [ :workspace_token, :name ], unique: true

    # What a word means for one client. "meaning" holds field values
    # ({"fields": {"finish": "#4"}}) and/or a part number.
    create_table :client_terms do |t|
      t.references :client, null: false, foreign_key: { on_delete: :cascade }
      t.string :term, null: false
      t.json :meaning, null: false
      t.string :source, null: false
      t.integer :times_confirmed, null: false, default: 1
      t.integer :last_match_request_id
      t.timestamps
    end
    add_index :client_terms, [ :client_id, :term ], unique: true

    create_table :match_requests do |t|
      t.references :client, null: false, foreign_key: { on_delete: :cascade }
      t.text :description, null: false
      t.string :outcome, null: false
      t.json :result, null: false
      t.json :approved_part_numbers
      t.decimal :quantity, precision: 18, scale: 4
      t.integer :quote_id
      t.datetime :approved_at
      t.timestamps
    end
  end
end
