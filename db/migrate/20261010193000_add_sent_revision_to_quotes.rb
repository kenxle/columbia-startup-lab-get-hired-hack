class AddSentRevisionToQuotes < ActiveRecord::Migration[8.1]
  def change
    add_column :quotes, :sent_at, :datetime
    add_column :quotes, :sent_review_revision, :string
  end
end
