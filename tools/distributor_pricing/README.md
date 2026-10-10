# Distributor pricing

Ruby RFQ-to-price service with live source refresh, five independent competitors per item, evidenced procurement costs and a 15% target / 8% minimum gross margin.

See [contracts, policy and source limitations](../../docs/data/DISTRIBUTOR_PRICING_AGENT.md). Run `ruby bin/quote` from this folder, passing a JSON RFQ on stdin. No procurement feed is configured by default, so public-only inputs remain held rather than receiving an unsupported selling price.

Run tests from the repository root:

```sh
ruby -Itools/distributor_pricing/test -e 'Dir["tools/distributor_pricing/test/*_test.rb"].each { |path| require_relative path }'
```
