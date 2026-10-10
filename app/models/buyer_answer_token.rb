class BuyerAnswerToken < ApplicationRecord
  belongs_to :quote
  belongs_to :quote_line
end
