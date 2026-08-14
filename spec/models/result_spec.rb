# frozen_string_literal: true

require "rails_helper"

RSpec.describe Result, type: :model do
  let(:user) { User.create!(email: "test@example.com", password: "password") }
  let(:search) { Search.create!(title: "Ruby Lead", query_conditions: "ruby", user: user) }

  describe "associations" do
    it "belongs to search" do
      association = described_class.reflect_on_association(:search)
      expect(association.macro).to eq(:belongs_to)
    end
  end

  describe "validations" do
    it "is valid with a valid status" do
      %w[unread watched garbage interesting].each do |valid_status|
        result = described_class.new(search: search, status: valid_status, url_hash: "hash_#{valid_status}")
        expect(result).to be_valid
      end
    end

    it "is invalid with an invalid status" do
      result = described_class.new(search: search, status: "invalid_status", url_hash: "hash_invalid")
      expect(result).not_to be_valid
      expect(result.errors[:status]).to include("is not included in the list")
    end
  end

  describe "scopes" do
    let!(:unread_result) do
      described_class.create!(
        search: search,
        title: "Senior Ruby Developer",
        content: "Awesome remote job",
        url: "https://example.com/job1",
        url_hash: "hash_job1",
        status: "unread",
        created_at: 2.hours.ago
      )
    end

    let!(:garbage_result) do
      described_class.create!(
        search: search,
        title: "Python Developer",
        content: "Legacy code base",
        url: "https://test.org/job2",
        url_hash: "hash_job2",
        status: "garbage",
        created_at: 3.days.ago
      )
    end

    let!(:old_result) do
      described_class.create!(
        search: search,
        title: "Elixir Specialist",
        content: "Functional programming",
        url: "https://elixir.io/job3",
        url_hash: "hash_job3",
        status: "watched",
        created_at: 2.months.ago
      )
    end

    describe ".without_garbage" do
      it "excludes results with garbage status" do
        expect(described_class.without_garbage).to include(unread_result, old_result)
        expect(described_class.without_garbage).not_to include(garbage_result)
      end
    end

    describe ".by_status" do
      it "filters results by given status" do
        expect(described_class.by_status("garbage")).to contain_exactly(garbage_result)
      end
    end

    describe ".search_by_keyword" do
      context "when query is blank or less than 3 characters" do
        it "returns all records" do
          expect(described_class.search_by_keyword(nil).count).to eq(3)
          expect(described_class.search_by_keyword("").count).to eq(3)
          expect(described_class.search_by_keyword("  ").count).to eq(3)
          expect(described_class.search_by_keyword("ab").count).to eq(3)
        end
      end

      context "when query is valid (>= 3 chars)" do
        it "searches case-insensitively across title, content, and url" do
          expect(described_class.search_by_keyword("ruby")).to contain_exactly(unread_result)
          expect(described_class.search_by_keyword("LEGACY")).to contain_exactly(garbage_result)
          expect(described_class.search_by_keyword("elixir.io")).to contain_exactly(old_result)
        end

        it "sanitizes SQL wildcard characters" do
          expect { described_class.search_by_keyword("%ruby_") }.not_to raise_error
        end
      end
    end

    describe ".by_time_frame" do
      it "filters by 'day'" do
        expect(described_class.by_time_frame("day")).to contain_exactly(unread_result)
      end

      it "filters by 'week'" do
        expect(described_class.by_time_frame("week")).to contain_exactly(unread_result, garbage_result)
      end

      it "filters by 'month'" do
        expect(described_class.by_time_frame("month")).to contain_exactly(unread_result, garbage_result)
      end

      it "filters by 'year'" do
        expect(described_class.by_time_frame("year")).to contain_exactly(unread_result, garbage_result, old_result)
      end

      it "returns all records for unknown or nil frame" do
        expect(described_class.by_time_frame(nil).count).to eq(3)
        expect(described_class.by_time_frame("invalid").count).to eq(3)
      end
    end
  end

  describe ".top_domains_efficiency" do
    before do
      described_class.create!(search: search, status: "unread", url: "https://rubyonrails.org/1", url_hash: "hash_rails_1")
      described_class.create!(search: search, status: "unread", url: "https://rubyonrails.org/2", url_hash: "hash_rails_2")
      described_class.create!(search: search, status: "unread", url: "http://github.com/1", url_hash: "hash_github_1")
    end

    it "extracts domain from URL, aggregates, and limits to top 5" do
      result = described_class.top_domains_efficiency

      expect(result["rubyonrails.org"]).to eq(2)
      expect(result["github.com"]).to eq(1)
    end
  end

  describe "callbacks" do
    describe "#broadcast_acknowledged" do
      let(:search_two) { Search.create!(title: "Other Search", query_conditions: "rails", user: user) }

      let!(:result1) do
        described_class.create!(
          search: search,
          url_hash: "same_hash_123",
          url: "https://example.com",
          status: "unread",
          acknowledged: false
        )
      end

      let!(:result2) do
        described_class.create!(
          search: search_two,
          url_hash: "same_hash_123",
          url: "https://example.com",
          status: "unread",
          acknowledged: false
        )
      end

      context "when status updates to non-unread (e.g. watched)" do
        it "marks all records with the same url_hash as acknowledged" do
          expect do
            result1.update!(status: "watched")
          end.to change { result2.reload.acknowledged }.from(false).to(true)
        end
      end

      context "when status remains unread" do
        it "does not update acknowledged flag" do
          expect do
            result1.update!(title: "New Title")
          end.not_to(change { result2.reload.acknowledged })
        end
      end
    end
  end
end
