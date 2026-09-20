# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::BatchPersister, type: :service do
  let(:user) { User.create!(email: "persister_test@example.com", password: "password123") }
  let(:search) do
    Search.create!(
      user: user,
      title: "Ruby Backend",
      query_conditions: "ruby",
      status: "pending"
    )
  end

  let(:url1) { "https://example.com/jobs/1" }
  let(:hash1) { Digest::SHA256.hexdigest(url1) }

  let(:url2) { "https://example.com/jobs/2" }
  let(:hash2) { Digest::SHA256.hexdigest(url2) }

  let(:valid_records) do
    [
      {
        "url" => url1,
        "url_hash" => hash1,
        "title" => "Developer 1",
        "content" => "Ruby content",
        "engine" => "google",
        "relevance_score" => 80
      },
      {
        "url" => url2,
        "url_hash" => hash2,
        "title" => "Developer 2",
        "content" => "Rails content",
        "engine" => "bing",
        "relevance_score" => 90
      }
    ]
  end

  describe ".call" do
    subject { described_class.call(search.id, result_records) }

    context "when input records are blank or nil" do
      let(:result_records) { [] }

      it "returns zero counts and does not insert anything" do
        expect { subject }.not_to change(Result, :count)
        expect(subject).to eq({ raw_count: 0, new_count: 0 })
      end

      context "when nil is passed" do
        let(:result_records) { nil }

        it "returns zero counts safely" do
          expect { subject }.not_to change(Result, :count)
          expect(subject).to eq({ raw_count: 0, new_count: 0 })
        end
      end
    end

    context "when processing new valid records" do
      let(:result_records) { valid_records }

      it "persists new records in the database" do
        expect { subject }.to change(Result, :count).by(2)

        inserted_urls = Result.where(search_id: search.id).pluck(:url)
        expect(inserted_urls).to match_array([url1, url2])
      end

      it "sets default values for status, acknowledged, and verification_status" do
        subject

        res1 = Result.find_by(search_id: search.id, url_hash: hash1)
        expect(res1.status).to eq("unread")
        expect(res1.acknowledged).to be(false)
        expect(res1.verification_status).to eq("pending")
      end

      it "returns correct raw_count and new_count metrics" do
        expect(subject).to eq({ raw_count: 2, new_count: 2 })
      end
    end

    context "when records contain internal duplicates within the same batch" do
      let(:result_records) do
        [
          { "url" => url1, "url_hash" => hash1, "title" => "First Occurrence" },
          { "url" => url1, "url_hash" => hash1, "title" => "Duplicate Occurrence" }
        ]
      end

      it "deduplicates records by url_hash before inserting" do
        expect { subject }.to change(Result, :count).by(1)

        result = Result.find_by(search_id: search.id, url_hash: hash1)
        expect(result.title).to eq("First Occurrence")
      end

      it "returns original raw_count and deduplicated new_count" do
        expect(subject).to eq({ raw_count: 2, new_count: 1 })
      end
    end

    context "when updating existing records (upsert behavior)" do
      let!(:existing_result) do
        Result.create!(
          search_id: search.id,
          url: url1,
          url_hash: hash1,
          title: "Old Title",
          content: "Old Content",
          relevance_score: 50,
          status: "unread"
        )
      end

      let(:result_records) do
        [
          {
            "url" => url1,
            "url_hash" => hash1,
            "title" => "Updated Title",
            "content" => "Updated Content",
            "relevance_score" => 95
          }
        ]
      end

      it "does not increase total record count" do
        expect { subject }.not_to change(Result, :count)
      end

      it "updates specified columns in upsert_all without throwing PostgreSQL syntax errors" do
        expect { subject }.not_to raise_error

        existing_result.reload
        expect(existing_result.title).to eq("Updated Title")
        expect(existing_result.content).to eq("Updated Content")
        expect(existing_result.relevance_score).to eq(95)
      end

      it "returns new_count as 0 for already existing records in current search" do
        expect(subject).to eq({ raw_count: 1, new_count: 0 })
      end
    end

    context "when cross-search global acknowledged inheritance applies" do
      let!(:other_search) do
        Search.create!(
          user: user,
          title: "Other Search",
          query_conditions: "rails",
          status: "completed"
        )
      end

      let(:result_records) { valid_records }

      context "when a URL was already acknowledged in another search" do
        before do
          res = Result.create!(
            search_id: other_search.id,
            url: url1,
            url_hash: hash1,
            title: "Old Job",
            content: "Old Content",
            status: "watched"
          )
          # Оновлюємо напряму, якщо поле заблоковане readonly/default атрибутами
          Result.where(id: res.id).update_all(acknowledged: true)
        end

        it "sets acknowledged: true for matching url_hash" do
          subject

          res1 = Result.find_by(search_id: search.id, url_hash: hash1)
          res2 = Result.find_by(search_id: search.id, url_hash: hash2)

          expect(res1.acknowledged).to be(true)
          expect(res2.acknowledged).to be(false)
        end
      end

      context "when a URL exists globally but was NOT acknowledged" do
        before do
          res = Result.create!(
            search_id: other_search.id,
            url: url1,
            url_hash: hash1,
            title: "Old Job",
            content: "Old Content",
            status: "unread"
          )
          Result.where(id: res.id).update_all(acknowledged: false)
        end

        it "keeps acknowledged: false for the new result" do
          subject

          res1 = Result.find_by(search_id: search.id, url_hash: hash1)
          expect(res1.acknowledged).to be(false)
        end
      end
    end
  end
end
