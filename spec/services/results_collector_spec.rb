# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchEngines::ResultsCollector do
  let(:query) { "site:example.com" }
  let(:options) { { time_range: "day" } }

  describe ".call with block (streaming mode)" do
    let(:raw_data1) { [{ "url" => "https://example.com/1" }, { "url" => "https://example.com/2" }] }
    let(:raw_data2) { [{ "url" => "https://example.com/2" }, { "url" => "https://example.com/3" }] }

    before do
      allow(SearchEngines::Yacy::RawResultsCollector).to receive(:call)
        .and_return({ data: raw_data1, failed_engines: [], error: nil })

      allow(SearchEngines::Searxng::RawResultsCollector).to receive(:call)
        .and_return({ data: raw_data2, failed_engines: [], error: nil })

      allow(SearchEngines::Fourget::RawResultsCollector).to receive(:call)
        .and_return({ data: [], failed_engines: ["Fourget"], error: "Timeout" })

      allow(SearchEngines::Degoog::RawResultsCollector).to receive(:call)
        .and_return({ data: [], failed_engines: [], error: nil })
    end

    it "yields deduplicated batches to the provided block" do
      yielded_batches = []

      summary = described_class.call(query, options) do |batch, collector_name|
        yielded_batches << [collector_name, batch]
      end

      expect(yielded_batches.size).to eq(2)

      expect(yielded_batches[0][0]).to eq("SearchEngines::Yacy::RawResultsCollector")
      expect(yielded_batches[0][1]).to eq(raw_data1)

      expect(yielded_batches[1][0]).to eq("SearchEngines::Searxng::RawResultsCollector")
      expect(yielded_batches[1][1]).to eq([{ "url" => "https://example.com/3" }])

      expect(summary).to eq({
                              success: true,
                              failed_engines: ["Fourget"],
                              error: nil
                            })
    end

    it "yields to block using spy matcher" do
      block_spy = double("block_receiver")
      allow(block_spy).to receive(:call)

      described_class.call(query, options) do |batch, collector_name|
        block_spy.call(batch, collector_name)
      end

      expect(block_spy).to have_received(:call).with(raw_data1, "SearchEngines::Yacy::RawResultsCollector")
      expect(block_spy).to have_received(:call).with(
        [{ "url" => "https://example.com/3" }],
        "SearchEngines::Searxng::RawResultsCollector"
      )
    end
  end

  describe ".call without block (accumulative mode)" do
    before do
      allow(SearchEngines::Yacy::RawResultsCollector).to receive(:call)
        .and_return({ data: [{ "url" => "https://example.com/1" }], failed_engines: [], error: nil })

      allow(SearchEngines::Searxng::RawResultsCollector).to receive(:call)
        .and_return({ data: [], failed_engines: [], error: nil })

      allow(SearchEngines::Fourget::RawResultsCollector).to receive(:call)
        .and_return({ data: [], failed_engines: [], error: nil })

      allow(SearchEngines::Degoog::RawResultsCollector).to receive(:call)
        .and_return({ data: [], failed_engines: [], error: nil })
    end

    it "collects all data into combined_data array" do
      result = described_class.call(query, options)

      expect(result[:success]).to be true
      expect(result[:data]).to eq([{ "url" => "https://example.com/1" }])
      expect(result[:failed_engines]).to be_empty
    end
  end
end
