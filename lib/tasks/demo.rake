namespace :demo do
  desc "Refresh receipt timing for untouched, known development demo RFQs"
  task refresh_timing: :environment do
    counts = QuoteWorkspace::DemoWorkspace.refresh_timing!
    puts "Refreshed: #{counts[:refreshed]}; skipped: #{counts[:skipped]}"
  end
end
