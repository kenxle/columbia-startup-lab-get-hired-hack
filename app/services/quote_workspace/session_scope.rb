module QuoteWorkspace
  # Scopes quotes to an opaque token held in the Rails session, so one
  # browser cannot reach another browser's RFQs by guessing record IDs.
  # This is local development scoping, not production authentication.
  module SessionScope
    extend ActiveSupport::Concern

    SESSION_KEY = :quote_workspace_token
    TOKEN_PATTERN = /\A[A-Za-z0-9_-]{43}\z/

    private

    def workspace_token
      token = session[SESSION_KEY]
      unless token.is_a?(String) && token.match?(TOKEN_PATTERN)
        token = SecureRandom.urlsafe_base64(32)
        session[SESSION_KEY] = token
      end
      token
    end

    def workspace_quotes
      Quote.for_workspace(workspace_token)
    end
  end
end
