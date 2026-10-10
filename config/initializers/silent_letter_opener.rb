if Rails.env.development?
  require Rails.root.join("lib/quote_workspace/silent_letter_opener")

  ActiveSupport.on_load(:action_mailer) do
    add_delivery_method :silent_letter_opener, QuoteWorkspace::SilentLetterOpener,
      location: Rails.root.join("tmp/letter_opener").to_s
  end
end
