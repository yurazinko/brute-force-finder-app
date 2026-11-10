# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::BulkUpdateService, type: :service do
  let(:user) { create(:user) }
  let(:search) { create(:search, user: user) }

  let!(:result1) { create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 150) }
  let!(:result2) { create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 120) }
  let!(:result3) { create(:result, search: search, status: "unread", acknowledged: false, relevance_score: 50) }

  let(:filter_options) { { status: "unread" } }

  describe "#call" do
    context "with valid parameters and status 'watched'" do
      it "updates status to watched, sets acknowledged to true, and returns updated count" do
        service = described_class.new(
          search: search,
          target_status: "watched",
          visible_ids: [result1.id, result2.id],
          filter_options: filter_options
        )

        expect { service.call }.to change { result1.reload.status }.from("unread").to("watched")
                               .and change { result1.reload.acknowledged }.from(false).to(true)
                               .and change { result2.reload.status }.from("unread").to("watched")
                               .and change { result2.reload.acknowledged }.from(false).to(true)

        # result3 не передавався у visible_ids, тому лишився без змін
        expect(result3.reload.status).to eq("unread")
        expect(result3.acknowledged).to be(false)
      end

      it "returns the number of updated records" do
        service = described_class.new(
          search: search,
          target_status: "watched",
          visible_ids: [result1.id, result2.id],
          filter_options: filter_options
        )

        expect(service.call).to eq(2)
      end
    end

    context "with scope_mode all_matching" do
      it "updates every result in the active query scope without requiring visible IDs" do
        service = described_class.new(
          search: search,
          target_status: "watched",
          visible_ids: [],
          filter_options: filter_options,
          scope_mode: "all_matching"
        )

        expect(service.call).to eq(2)
        expect(result1.reload.status).to eq("watched")
        expect(result2.reload.status).to eq("watched")
        expect(result3.reload.status).to eq("unread")
      end

      it "applies the currently selected less-relevant bucket across all matching records" do
        service = described_class.new(
          search: search,
          target_status: "garbage",
          visible_ids: [],
          filter_options: { status: "unread", show_less_relevant: "true" },
          scope_mode: "all_matching"
        )

        expect(service.call).to eq(1)
        expect(result1.reload.status).to eq("unread")
        expect(result2.reload.status).to eq("unread")
        expect(result3.reload.status).to eq("garbage")
      end
    end

    context "with target status 'unread'" do
      before do
        result1.update!(status: "watched", acknowledged: true)
      end

      it "updates status to unread and resets acknowledged to false" do
        service = described_class.new(
          search: search,
          target_status: "unread",
          visible_ids: [result1.id],
          filter_options: { status: "watched" }
        )

        expect { service.call }.to change { result1.reload.status }.from("watched").to("unread")
                               .and change { result1.reload.acknowledged }.from(true).to(false)
      end
    end

    context "with target status 'garbage' or 'interesting'" do
      it "updates status correctly without forcing acknowledged to true" do
        service = described_class.new(
          search: search,
          target_status: "garbage",
          visible_ids: [result1.id],
          filter_options: filter_options
        )

        service.call

        expect(result1.reload.status).to eq("garbage")
      end
    end

    context "with invalid target status" do
      it "does not update any records and returns 0" do
        service = described_class.new(
          search: search,
          target_status: "invalid_status",
          visible_ids: [result1.id],
          filter_options: filter_options
        )

        expect { service.call }.not_to(change { result1.reload.status })
        expect(service.call).to eq(0)
      end
    end

    context "when visible_ids is empty" do
      it "does not update any records and returns 0" do
        service = described_class.new(
          search: search,
          target_status: "watched",
          visible_ids: [],
          filter_options: filter_options
        )

        expect { service.call }.not_to(change { result1.reload.status })
        expect(service.call).to eq(0)
      end
    end
  end
end
