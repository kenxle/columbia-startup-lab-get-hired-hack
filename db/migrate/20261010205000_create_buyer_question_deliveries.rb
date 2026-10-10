class CreateBuyerQuestionDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :buyer_question_deliveries do |t|
      t.references :quote, null: false, foreign_key: { on_delete: :cascade }
      t.references :quote_line, null: true, foreign_key: { on_delete: :nullify }
      t.string :fingerprint, null: false
      t.string :channel, null: false, default: "local_preview"
      t.string :status, null: false, default: "pending"
      t.string :recipient, null: false
      t.string :buyer_name
      t.integer :line_position, null: false
      t.string :source_line_id
      t.text :question_text, null: false
      t.datetime :previewed_at
      t.string :error_message
      t.timestamps
    end
    add_index :buyer_question_deliveries, [:quote_line_id, :fingerprint, :channel], unique: true, name: "index_question_delivery_identity"
  end
end
