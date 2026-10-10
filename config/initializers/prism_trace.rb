require Rails.root.join("tools/rfq_processing/lib/rfq_processing/openai_compatible_client").to_s

Rails.application.config.to_prepare do
  CatalogMatch::LlmReader.trace_listener = ->(**event) { QuoteWorkspace::PrismTrace.enqueue(event) }

  client = RfqProcessing::OpenAiCompatibleClient
  if client.respond_to?(:trace_listener=)
    client.trace_listener = lambda do |**event|
      outcome = { "http_success" => "ok", "http_error" => "gateway_error", "network_error" => "gateway_error" }
        .fetch(event[:outcome], "unparseable")
      QuoteWorkspace::PrismTrace.enqueue(event.slice(:model, :elapsed_ms, :run_id).merge(outcome: outcome))
    rescue StandardError
      false # Telemetry must never interrupt RFQ processing, including reloads.
    end
  end
end
