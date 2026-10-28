# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::UpdateStatusService, type: :service do
  let(:user) { User.create!(username: "service_tester", password: "password") }
  let(:category) { Category.create!(name: "General", user: user) }
  let(:search1) { Search.create!(title: "Search One", query_conditions: "query1", user: user) }
  let(:search2) { Search.create!(title: "Search Two", query_conditions: "query2", user: user) }

  let!(:result) do
    Result.create!(
      search: search1,
      status: "unread",
      acknowledged: false,
      url: "https://example.com/job",
      url_hash: "shared_hash_123"
    )
  end

  let!(:duplicate_result) do
    Result.create!(
      search: search2,
      status: "unread",
      acknowledged: false,
      url: "https://example.com/job",
      url_hash: "shared_hash_123"
    )
  end

  describe "#call" do
    context "when status changes from unread to another state (e.g., 'watched')" do
      it "updates the status, marks the record as acknowledged, and propagates to all results with the same url_hash" do
        service = described_class.new(result: result, status: "watched")
        success = service.call

        expect(success).to be true

        expect(result.reload.status).to eq("watched")
        expect(result.acknowledged).to be true
        expect(duplicate_result.reload.acknowledged).to be true
      end
    end

    context "when status remains 'unread'" do
      it "updates successfully without propagating acknowledged" do
        service = described_class.new(result: result, status: "unread")
        success = service.call

        expect(success).to be true

        expect(result.reload.status).to eq("unread")
        expect(result.reload.acknowledged).to be false
        expect(duplicate_result.reload.acknowledged).to be false
      end
    end

    context "when an error occurs during update (RecordInvalid)" do
      it "catches the exception, rolls back the transaction, and returns false" do
        allow(result).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(result))

        service = described_class.new(result: result, status: "watched")
        success = service.call

        expect(success).to be false
        expect(result.reload.status).to eq("unread")
      end
    end
  end
end
