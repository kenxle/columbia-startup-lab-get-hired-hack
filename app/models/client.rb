# A buyer company. Each client has its own memory of what its words mean.
class Client < ApplicationRecord
  has_many :client_terms, dependent: :delete_all
  has_many :match_requests, dependent: :delete_all

  scope :for_workspace, ->(workspace_token) { where(workspace_token: workspace_token.to_s) }

  validates :name, presence: true, length: { maximum: 200 }, uniqueness: { scope: :workspace_token, case_sensitive: false }
  validates :workspace_token, presence: true

  normalizes :name, with: ->(name) { name.to_s.squish }
end
