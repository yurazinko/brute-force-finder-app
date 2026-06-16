# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchActivator, type: :service do
  let(:category) { Category.create!(name: "SaaS Platforms") }
  let!(:target_lever) { Target.create!(category: category, name: "Lever", domain: "lever.co", is_active: true) }
  let!(:target_greenhouse) { Target.create!(category: category, name: "Greenhouse", domain: "greenhouse.io", is_active: true) }
  let!(:target_inactive) { Target.create!(category: category, name: "Broken Board", domain: "broken.com", is_active: false) }

  let(:search) do
    Search.create!(
      title: "Elixir/Ruby Backend",
      query_conditions: "(ruby OR elixir) (remote)",
      status: "processing"
    )
  end

  describe ".call" do
    context "when providing valid and active target IDs" do
      let(:target_ids) { [target_lever.id, target_greenhouse.id, target_inactive.id] }

      it "bulk inserts prompts only for active targets" do
        expect do
          described_class.call(search, target_ids)
        end.to change(Prompt, :count).by(2)
      end

      it "creates prompts with correct structural data" do
        described_class.call(search, target_ids)

        lever_prompt = Prompt.find_by(target: target_lever, search: search)
        expect(lever_prompt.full_query_text).to eq("site:lever.co (ruby OR elixir) (remote)")
        expect(lever_prompt.status).to eq("pending")
      end

      it "updates the search status to pending" do
        described_class.call(search, target_ids)
        expect(search.reload.status).to eq("processing")
      end

      it "returns true upon successful execution" do
        expect(described_class.call(search, target_ids)).to be_truthy
      end
    end

    context "when a prompt conflict occurs (idempotency check via upsert)" do
      let(:target_ids) { [target_lever.id] }

      before do
        another_search = Search.create!(title: "Old Search", query_conditions: search.query_conditions, status: "processing")
        Prompt.create!(
          search: another_search,
          target: target_lever,
          full_query_text: "site:lever.co #{search.query_conditions}",
          status: "success"
        )
      end

      it "does not create a new database row and runs successfully" do
        expect do
          described_class.call(search, target_ids)
        end.not_to change(Prompt, :count)
      end

      it "updates the existing prompt with the new search_id and resets status" do
        described_class.call(search, target_ids)

        existing_prompt = Prompt.find_by(target: target_lever)
        expect(existing_prompt.search_id).to eq(search.id)
        expect(existing_prompt.status).to eq("pending")
      end
    end

    context "when edge-case parameters are passed" do
      it "returns false immediately if target_ids is empty" do
        expect(described_class.call(search, [])).to be_falsy
        expect(Prompt.count).to eq(0)
      end

      it "returns false immediately if target_ids is nil" do
        expect(described_class.call(search, nil)).to be_falsy
        expect(Prompt.count).to eq(0)
      end

      it "returns false if targets exist but none of them are active" do
        expect(described_class.call(search, [target_inactive.id])).to be_falsy
        expect(Prompt.count).to eq(0)
        expect(search.reload.status).to eq("processing")
      end
    end

    context "when a critical database failure occurs" do
      let(:target_ids) { [target_lever.id] }

      before do
        allow(Prompt).to receive(:upsert_all).and_raise(ActiveRecord::ActiveRecordError.new("Deadlock or PG Error"))
        allow(Rails.logger).to receive(:error)
      end

      it "rescues the exception, logs it and returns false gracefully" do
        expect(described_class.call(search, target_ids)).to be_falsy
        expect(search.reload.status).to eq("processing")
      end

      it "logs the clean error message with context data" do
        described_class.call(search, target_ids)
        expect(Rails.logger).to have_received(:error).with(/Critical failure during activation for Search##{search.id}/)
      end
    end
  end
end
