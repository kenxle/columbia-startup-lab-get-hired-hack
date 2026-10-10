# Block Convey PRISM metadata tracing

Optional integration through `CatalogMatch::LlmReader.trace_listener`. It records model name, measured latency and outcome. Original prompts, model replies, RFQs, buyer details and provider request IDs are omitted. Required message fields contain clearly marked synthetic metadata envelopes. These traces do not establish answer quality, successful interpretation, or live model use.

An optional `run_id` is accepted only as a UUID in the standard 8-4-4-4-12 hexadecimal format. It is normalized to lowercase, retained in trace metadata and used as `session_id: metadata-<UUID>`. Missing or invalid IDs receive a fresh random UUID for that trace's metadata and session. Quote IDs, RFQ references, buyer identifiers and other arbitrary strings are never used as trace run identifiers. Callers must supply the same safe UUID to correlate events from one run; an automatically generated ID does not imply that a model run occurred.

The [official API contract](https://blockconvey.com/docs) was checked on 2026-10-10: HTTPS POST `https://prism.blockconvey.com/api/traces`, `X-PRISMtrace-Key` authentication, and required project/model/messages/latency fields. A stored trace ID in a successful response confirms ingestion.

Set `PRISMTRACE_API_KEY` and `PRISMTRACE_PROJECT_ID` in ignored `.env`, then restart Rails. Both are required. Never paste credentials in the bulletin or commit them. Missing configuration disables sending.

The hook queues `PrismTraceJob`. Inline execution is refused. It accepts at most 20 events per minute per process, uses bounded sanitized payloads and a single HTTP attempt with 2-second connect and 3-second read/write timeouts. Errors never affect quoting. Background delivery is best effort; a queued event is not a confirmed trace. The hook only observes actual catalog-reader calls; it does not enable that reader or the separate RFQ parser.

## Explicit synthetic connectivity check

After configuring credentials, this command sends one clearly synthetic metadata-only test event. It does not invoke an AI model:

```sh
script/with-ruby bin/rails runner 'puts QuoteWorkspace::PrismTrace.call({model: "claude-opus-5", elapsed_ms: 0, outcome: "synthetic_smoke"}).to_json'
```

Use the returned trace ID to inspect PRISM. `disabled`, `failed`, `rejected` or `unconfirmed` is not proof of ingestion. No live trace or successful account connection was claimed during implementation. To demonstrate real hook activity, run a separately authorized catalog-reader invocation and check its resulting trace in PRISM.

Tests use injected HTTP responses and never contact PRISM:

```sh
script/with-ruby bin/rails test test/models/prism_trace_test.rb
```
