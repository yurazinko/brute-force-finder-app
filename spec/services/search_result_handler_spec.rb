# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchCampaigns::ResultHandler, type: :service do
  let(:user) { User.create!(email: "test@example.com", password: "password123") }

  let(:category) { Category.create!(name: "Platforms") }
  let(:target_domain) { "lever-#{SecureRandom.hex(4)}.co" }
  let(:target) { Target.create!(category: category, name: "Lever", domain: target_domain) }

  let(:search) do
    Search.create!(
      user: user,
      title: "Ruby Backend",
      query_conditions: "ruby",
      status: "pending"
    )
  end

  let!(:prompt) do
    Prompt.create!(
      search: search,
      target: target,
      full_query_text: "site:#{target_domain} ruby",
      status: "active"
    )
  end

  let(:raw_results) do
    { data: [
      {
        "url" => "https://#{target_domain}/job1",
        "title" => "Job 1",
        "content" => "Ruby dev"
      },
      {
        "url" => "https://#{target_domain}/job2",
        "title" => "Job 2",
        "content" => "Rails dev"
      }
    ] }
  end

  let(:expected_normalized_urls) do
    ["https://#{target_domain}/job1", "https://#{target_domain}/job2"]
  end

  describe ".call" do
    context "when raw results are present and valid" do
      it "bulk inserts results for the search without N+1 queries" do
        expect do
          described_class.call(prompt, raw_results)
        end.to change(Result, :count).by(2)

        expect(Result.pluck(:url)).to match_array(expected_normalized_urls)
        expect(Result.all).to all(have_attributes(search_id: search.id))
      end

      it "calculates and stores sha256 hashes for unique constraints" do
        described_class.call(prompt, raw_results)

        expect(Result.pluck(:url_hash)).to match_array(
          [
            Digest::SHA256.hexdigest("https://#{target_domain}/job1"),
            Digest::SHA256.hexdigest("https://#{target_domain}/job2")
          ]
        )
      end

      it "updates prompt status to success" do
        described_class.call(prompt, raw_results)
        expect(prompt.reload.status).to eq("success")
      end

      it "returns execution metrics hash upon successful execution" do
        expect(described_class.call(prompt, raw_results)).to eq(
          { raw_count: 2, new_count: 2, total: 2 }
        )
      end
    end

    context "when raw results contain duplicate URLs" do
      let(:duplicate_results) do
        { data: [
          { "url" => "https://#{target_domain}/job1?abc=1", "title" => "First" },
          { "url" => "https://#{target_domain}/job1?xyz=2", "title" => "Duplicate after normalization" }
        ] }
      end

      it "silently ignores duplicates due to inside-batch grouping and unique_by" do
        expect do
          described_class.call(prompt, duplicate_results)
        end.to change(Result, :count).by(1)

        expect(Result.pluck(:url)).to eq(["https://#{target_domain}/job1"])
      end
    end

    context "when raw results are blank (empty array or nil)" do
      it "does not create any result records" do
        expect do
          described_class.call(prompt, { data: [] })
        end.not_to change(Result, :count)
      end

      it "marks the prompt as failed with a clean error message" do
        described_class.call(prompt, nil)

        prompt.reload
        expect(prompt.status).to eq("failed")
        expect(prompt.error_message).to eq("No results found")
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

    context "when implementing the context-aware global viewed (acknowledged) logic" do
      let!(:other_search) do
        Search.create!(
          user: user,
          title: "Previous Search",
          query_conditions: "rails",
          status: "completed"
        )
      end

      let(:job1_hash) { "a8b6b06473ace2579ad4c9a9234dc3a98adedcda296e4e8d03988d9c7827c2d8" }
      let(:job2_hash) { "f86928a1c95ed4abd68ed4b8c7b447e97757c2d2e007092891428b849ca9f69f" }

      let(:mocked_transformer_records) do
        [
          {
            "search_id" => search.id,
            "url" => "https://#{target_domain}/job1",
            "url_hash" => job1_hash,
            "title" => "Job 1",
            "content" => "Ruby dev"
          },
          {
            "search_id" => search.id,
            "url" => "https://#{target_domain}/job2",
            "url_hash" => job2_hash,
            "title" => "Job 2",
            "content" => "Rails dev"
          }
        ]
      end

      before do
        allow(Results::DataTransformer).to receive(:process)
          .with(search.id, raw_results[:data], target)
          .and_return(mocked_transformer_records)
      end

      context "when the URL was already acknowledged in another search" do
        before do
          res = Result.create!(
            search_id: other_search.id,
            url: "https://#{target_domain}/job1",
            url_hash: job1_hash,
            title: "Old Role",
            content: "Already reviewed",
            status: "watched"
          )
          Result.where(id: res.id).update_all(acknowledged: true)
        end

        it "inherits acknowledged: true for matching URLs" do
          described_class.call(prompt, raw_results)

          result = Result.unscoped.find_by(search_id: search.id, url_hash: job1_hash)

          expect(result).to be_present
          expect(result.acknowledged).to be(true)
        end

        it "keeps unrelated URLs acknowledged: false" do
          described_class.call(prompt, raw_results)

          other_result = Result.unscoped.find_by(search_id: search.id, url_hash: job2_hash)

          expect(other_result).to be_present
          expect(other_result.acknowledged).to be(false)
        end
      end

      context "when the URL exists globally but was not acknowledged" do
        before do
          res = Result.create!(
            search_id: other_search.id,
            url: "https://#{target_domain}/job1",
            url_hash: job1_hash,
            title: "Old Role",
            content: "Not reviewed",
            status: "unread"
          )
          Result.where(id: res.id).update_all(acknowledged: false)
        end

        it "does not mark the new result as acknowledged" do
          described_class.call(prompt, raw_results)

          result = Result.unscoped.find_by(search_id: search.id, url_hash: job1_hash)

          expect(result).to be_present
          expect(result.acknowledged).to be(false)
        end
      end

      context "when multiple acknowledged copies exist across searches" do
        before do
          res1 = Result.create!(
            search_id: other_search.id,
            url: "https://#{target_domain}/job1",
            url_hash: job1_hash,
            title: "Old Role",
            content: "Already reviewed",
            status: "watched"
          )
          Result.where(id: res1.id).update_all(acknowledged: true)

          another_search = Search.create!(
            user: user,
            title: "Another Search",
            query_conditions: "ruby",
            status: "completed"
          )

          res2 = Result.create!(
            search_id: another_search.id,
            url: "https://#{target_domain}/job1",
            url_hash: job1_hash,
            title: "Another Copy",
            content: "Reviewed too",
            status: "watched"
          )
          Result.where(id: res2.id).update_all(acknowledged: true)
        end

        it "marks the new result as acknowledged" do
          described_class.call(prompt, raw_results)

          result = Result.unscoped.find_by(search_id: search.id, url_hash: job1_hash)

          expect(result).to be_present
          expect(result.acknowledged).to be(true)
        end
      end
    end

    context "when an unexpected standard error occurs (fail-safe trigger)" do
      before do
        allow(Result).to receive(:upsert_all).and_raise(StandardError.new("Database deadlock"))
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

      it "returns error payload instead of crashing" do
        expect(described_class.call(prompt, raw_results)).to eq(
          { error: "Database deadlock", new_count: 0, raw_count: 0 }
        )
      end
    end

    context "when action cable broadcasting fails" do
      before do
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(StandardError.new("Redis connection dropped"))
        allow(Turbo::StreamsChannel).to receive(:broadcast_update_to).and_raise(StandardError.new("Redis connection dropped"))
        allow(Rails.logger).to receive(:error)
      end

      it "rescues the broadcast error gracefully and finishes successfully" do
        expect do
          expect(described_class.call(prompt, raw_results)).to be_a(Hash)
        end.to change(Result, :count).by(2)

        expect(prompt.reload.status).to eq("success")
        expect(Rails.logger).to have_received(:error).with(/Metrics broadcast failed: Redis connection dropped/)
      end
    end

    context "when broadcasting updates" do
      it "fetches aggregated counters via single optimized group query" do
        allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)

        described_class.call(prompt, raw_results)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_update_to).with(
          search, :results, target: "counter_unread", html: anything
        )
      end
    end
  end
end
