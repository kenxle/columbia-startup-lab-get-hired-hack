class AddLocalSendReceiptToQuotes < ActiveRecord::Migration[8.1]
  def change
    add_column :quotes, :sent_recipient, :string
    add_column :quotes, :sent_channel, :string
    add_column :quotes, :sent_preview_id, :string
  end
end
