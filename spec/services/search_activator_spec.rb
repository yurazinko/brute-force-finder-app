# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchCampaigns::Activator, type: :service do
  let(:category) { Category.create!(name: "SaaS Platforms") }
  let!(:target_lever) { Target.create!(category: category, name: "Lever", domain: "lever.co", is_active: true) }
  let!(:target_greenhouse) { Target.create!(category: category, name: "Greenhouse", domain: "greenhouse.io", is_active: true) }
  let!(:target_inactive) { Target.create!(category: category, name: "Broken Board", domain: "broken.com", is_active: false) }

  let(:search) do
    Search.create!(
      title: "Elixir/Ruby Backend",
      query_conditions: "(ruby OR elixir) (remote)",
      status: "pending"
    )
  end

  # Sidekiq testing helpers require clearing queues
  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_render_to)
    allow(PromptProcessorJob).to receive(:perform_at)
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

      it "updates the search status to processing" do
        described_class.call(search, target_ids)
        expect(search.reload.status).to eq("processing")
      end

      it "returns true upon successful execution" do
        expect(described_class.call(search, target_ids)).to be(true)
      end

      it "triggers Sidekiq workers with delayed execution" do
        described_class.call(search, target_ids)
        expect(PromptProcessorJob).to have_received(:perform_at).twice
      end

      it "broadcasts live status updating to Turbo Streams" do
        described_class.call(search, target_ids)
        expect(Turbo::StreamsChannel).to have_received(:broadcast_render_to).with(
          search, :results,
          template: "searches/update_status",
          assigns: { message: /Initializing 2 parallel scraping streams/ }
        )
      end
    end

    context "when a prompt conflict occurs (idempotency check via upsert)" do
      let(:target_ids) { [target_lever.id] }

      before do
        Prompt.create!(
          search: search,
          target: target_lever,
          full_query_text: "site:lever.co #{search.query_conditions}",
          status: "failed"
        )
      end

      it "does not create a new database row and runs successfully" do
        expect do
          described_class.call(search, target_ids)
        end.not_to change(Prompt, :count)
      end

      it "resets status to pending for retry execution without changing search_id" do
        described_class.call(search, target_ids)

        existing_prompt = Prompt.find_by(search: search, target: target_lever)
        expect(existing_prompt.status).to eq("pending")
      end
    end

    context "when edge-case parameters are passed" do
      context "when target_ids is empty" do
        it "triggers global search, creates 1 prompt without target and returns true" do
          expect { described_class.call(search, []) }.to change(Prompt, :count).by(1)

          global_prompt = Prompt.find_by(search: search, target: nil)
          expect(global_prompt.full_query_text).to eq(search.query_conditions)
          expect(search.reload.status).to eq("processing")
        end
      end

      context "when target_ids is nil" do
        it "triggers global search, creates 1 prompt without target and returns true" do
          expect { described_class.call(search, nil) }.to change(Prompt, :count).by(1)
          expect(search.reload.status).to eq("processing")
        end
      end

      context "when targets exist but none of them are active" do
        it "does not create any prompts, skips jobs and returns true" do
          expect { described_class.call(search, [target_inactive.id]) }.not_to change(Prompt, :count)
          expect(PromptProcessorJob).not_to have_received(:perform_at)
          expect(search.reload.status).to eq("processing")
        end
      end
    end

    context "when a critical database failure occurs" do
      let(:target_ids) { [target_lever.id] }

      before do
        allow(Prompt).to receive(:upsert_all).and_raise(ActiveRecord::ActiveRecordError.new("Deadlock or PG Error"))
        allow(Rails.logger).to receive(:error)
      end

      it "rescues the exception, logs it and returns false gracefully" do
        expect(described_class.call(search, target_ids)).to be(false)
        expect(search.reload.status).to eq("pending")
      end

      it "logs the clean error message with context data" do
        described_class.call(search, target_ids)
        expect(Rails.logger).to have_received(:error).with(/\[SearchCampaigns::Activator\] Critical failure for Search/)
      end
    end

    context "when live status broadcasting fails" do
      let(:target_ids) { [target_lever.id] }

      before do
        allow(Turbo::StreamsChannel).to receive(:broadcast_render_to).and_raise(StandardError.new("Redis down"))
        allow(Rails.logger).to receive(:error)
      end

      it "does not crash the transaction and returns true" do
        expect(described_class.call(search, target_ids)).to be(true)
        expect(search.reload.status).to eq("processing")
      end

      it "logs the broadcast error message separately" do
        described_class.call(search, target_ids)
        expect(Rails.logger).to have_received(:error).with(/\[SearchCampaigns::Activator\] Live status broadcast failed/)
      end
    end
  end
end
