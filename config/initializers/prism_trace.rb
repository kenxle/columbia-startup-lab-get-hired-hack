Rails.application.config.to_prepare do
  CatalogMatch::LlmReader.trace_listener = ->(**event) { QuoteWorkspace::PrismTrace.enqueue(event) }
end
