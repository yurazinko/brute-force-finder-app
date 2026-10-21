# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchCampaigns::ResultHandler, type: :service do
  let(:user) { User.create!(email: "test@example.com", password: "password123") }
  let(:search) { Search.create!(user: user, title: "Ruby Jobs", query_conditions: "ruby") }
  let(:prompt) { Prompt.create!(search: search, full_query_text: "site:github.com ruby", status: "active") }

  let(:raw_results) do
    {
      data: [
        { "url" => "https://github.com/ruby/ruby", "title" => "Ruby Repo" }
      ]
    }
  end

  describe ".call" do
    context "when raw results are present and valid" do
      it "processes records, persists them, and returns metrics summary" do
        allow(Results::DataTransformer).to receive(:process).and_return([{ url: "https://github.com/ruby/ruby" }])
        allow(Results::BatchPersister).to receive(:call).and_return({ raw_count: 1, new_count: 1, persisted_results: [] })
        allow(Results::Counters).to receive(:calculate_filtered).and_return(double(total: 1))
        allow(SearchCampaigns::LifecycleNotifier).to receive(:broadcast_metrics)

        result = described_class.call(prompt, raw_results)

        expect(result[:raw_count]).to eq(1)
        expect(result[:new_count]).to eq(1)
        expect(result[:total]).to eq(1)
      end
    end

    context "when raw results are blank" do
      it "returns zero metrics without failing" do
        result = described_class.call(prompt, { data: [] })

        expect(result[:raw_count]).to eq(0)
        expect(result[:new_count]).to eq(0)
      end
    end
  end
end
