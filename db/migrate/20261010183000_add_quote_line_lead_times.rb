class AddQuoteLineLeadTimes < ActiveRecord::Migration[8.1]
  def change
    add_column :quote_lines, :lead_time, :string
    add_column :quote_lines, :lead_time_source, :string
  end
end
