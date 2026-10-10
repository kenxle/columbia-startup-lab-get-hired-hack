class CreateBuyerAnswerTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :buyer_answer_tokens do |t|
      t.references :quote, null: false, foreign_key: { on_delete: :cascade }
      t.references :quote_line, null: false, foreign_key: { on_delete: :cascade }
      t.string :review_revision, null: false
      t.string :processing_revision, null: false
      t.string :question_fingerprint, null: false
      t.json :choice, null: false
      t.datetime :used_at
      t.timestamps
    end
  end
end
