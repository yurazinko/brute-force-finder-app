# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchResultHandler, type: :service do
  let(:category) { Category.create!(name: "Platforms") }
  let(:target) { Target.create!(category: category, name: "Lever", domain: "lever-#{SecureRandom.hex(4)}.co") }

  let(:search) do
    Search.create!(
      title: "Ruby Backend",
      query_conditions: "ruby",
      status: "pending"
    )
  end

  let!(:prompt) do
    Prompt.create!(
      search: search,
      target: target,
      full_query_text: "site:lever.co ruby",
      status: "active"
    )
  end

  let(:raw_results) do
    [
      { "url" => "https://lever.co/job1", "title" => "RoR Dev", "content" => "We need Ruby dev" },
      { "url" => "https://lever.co/job2", "title" => "Lead Ruby", "content" => "Senior rails role" }
    ]
  end

  describe ".call" do
    context "when raw results are present and valid" do
      it "bulk inserts results for the search without N+1 queries" do
        expect do
          described_class.call(prompt, raw_results)
        end.to change(Result, :count).by(2)

        expect(Result.pluck(:url)).to match_array(["https://lever.co/job1", "https://lever.co/job2"])
        expect(Result.all).to all(have_attributes(search_id: search.id))
      end

      it "updates prompt status to success" do
        described_class.call(prompt, raw_results)
        expect(prompt.reload.status).to eq("success")
      end

      it "returns true upon successful execution" do
        expect(described_class.call(prompt, raw_results)).to be_truthy
      end
    end

    context "when raw results are blank (empty array or nil)" do
      it "does not create any result records" do
        expect do
          described_class.call(prompt, [])
        end.not_to change(Result, :count)
      end

      it "marks the prompt as failed with a clean error message" do
        described_class.call(prompt, nil)

        prompt.reload
        expect(prompt.status).to eq("failed")
        expect(prompt.error_message).to eq("No results found or client error")
      end

      it "returns false gracefully" do
        expect(described_class.call(prompt, [])).to be_falsy
      end
    end

    context "when evaluating search completion lifecycle" do
      context "and this was the LAST remaining pending/active prompt" do
        it "automatically updates the search status to completed" do
          expect(search.status).to eq("pending")

          described_class.call(prompt, raw_results)

          expect(search.reload.status).to eq("completed")
        end
      end

      context "and there are STILL other active or pending prompts in this search" do
        before do
          another_target = Target.create!(category: category, name: "GH", domain: "gh-#{SecureRandom.hex(4)}.io")
          Prompt.create!(search: search, target: another_target, full_query_text: "site:gh.io ruby", status: "pending")
        end

        it "keeps the search status as pending" do
          described_class.call(prompt, raw_results)

          expect(search.reload.status).to eq("pending")
        end
      end
    end

    context "when an unexpected standard error occurs (fail-safe trigger)" do
      before do
        allow(Result).to receive(:insert_all).and_raise(StandardError.new("Database deadlock"))
        allow(Rails.logger).to receive(:error)
      end

      it "rescues the exception, marks prompt as failed and logs the issue" do
        expect do
          described_class.call(prompt, raw_results)
        end.not_to change(Result, :count)

        expect(prompt.reload.status).to eq("failed")
        expect(prompt.error_message).to eq("Database deadlock")
        expect(Rails.logger).to have_received(:error).with(/\[Search::ResultHandler\] Failed for Prompt/)
      end

      it "still triggers search completion check so the pipeline does not hang indefinitely" do
        described_class.call(prompt, raw_results)
        expect(search.reload.status).to eq("completed")
      end

      it "returns false instead of crashing the whole Sidekiq worker thread" do
        expect(described_class.call(prompt, raw_results)).to be_falsy
      end
    end
  end
end
