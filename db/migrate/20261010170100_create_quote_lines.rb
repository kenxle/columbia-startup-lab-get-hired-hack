class CreateQuoteLines < ActiveRecord::Migration[8.1]
  def change
    create_table :quote_lines do |table|
      table.references :quote, null: false, foreign_key: { on_delete: :cascade }
      table.integer :position, null: false
      table.string :description
      table.text :original_text
      table.json :spec
      table.decimal :quantity, precision: 18, scale: 4
      table.string :quantity_unit
      table.string :catalog_sku
      table.decimal :unit_price, precision: 18, scale: 4
      table.string :price_source
      table.string :state, null: false, default: "needs_buyer"
      table.text :clarification_question
      table.text :notes
      table.json :evidence
      table.json :compliance
      table.json :benchmark
      table.json :unresolved_fields
      table.json :edited_fields
      table.timestamps
    end

    add_index :quote_lines, [ :quote_id, :position ], unique: true
  end
end
