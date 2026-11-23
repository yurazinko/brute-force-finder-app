# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuickSearch::ResultBuilder, type: :service do
  let(:user) { create(:user) }
  let(:search) do
    Search.new(
      user: user,
      title: "Ruby on Rails developer",
      query_conditions: '"Ruby" "on" "Rails" "developer"',
      relevance_mode: "strict"
    )
  end

  let(:prompt) { Prompt.new(search: search, full_query_text: search.query_conditions, status: "active") }

  describe "#build" do
    it "builds unsaved models and assigns relevance metadata" do
      records = described_class.new(prompt: prompt).build([
                                                            {
                                                              url: "https://example.com/jobs/1?utm_source=test",
                                                              title: "Ruby on Rails developer",
                                                              content: "Ruby on Rails developer role",
                                                              engine: "SearXNG"
                                                            }
                                                          ])

      expect(records.size).to eq(1)
      expect(records.first).to be_a(Result)
      expect(records.first).to be_new_record
      expect(records.first.search).to equal(search)
      expect(prompt).to be_new_record
      expect(records.first.url).to eq("https://example.com/jobs/1")
      expect(records.first.relevance_score).to eq(100)
      expect(records.first.matched_keywords).to contain_exactly("Ruby", "on", "Rails", "developer")
      expect(records.first.verification_status).to eq("verified")
    end

    it "deduplicates URLs after normalization and never writes them to the database" do
      builder = described_class.new(prompt: prompt)

      expect do
        records = builder.build([
                                  { url: "https://www.example.com/jobs/1?utm_source=one", title: "Ruby Rails developer" },
                                  { url: "https://example.com/jobs/1?utm_source=two", title: "Ruby Rails developer" }
                                ])
        expect(records.size).to eq(1)
      end.not_to change(Result, :count)
    end

    it "filters results that do not match any keyword group" do
      records = described_class.new(prompt: prompt).build([
                                                            { url: "https://example.com/jobs/2", title: "Unrelated article", content: "Nothing relevant here" }
                                                          ])

      expect(records).to be_empty
    end

    it "skips malformed URLs" do
      records = described_class.new(prompt: prompt).build([
                                                            { url: "not a URL", title: "Ruby developer" }
                                                          ])

      expect(records).to be_empty
    end
  end
end
