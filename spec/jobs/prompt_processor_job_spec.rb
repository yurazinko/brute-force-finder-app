# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptProcessorJob, type: :job do
  let(:job) { described_class.new }
  let(:user) { User.create!(username: "test@example.com", password: "password123") }
  let(:search) { Search.create!(user: user, title: "Test Search", query_conditions: "ruby", time_frame: "month") }
  let(:category) { Category.create!(name: "Technology") } # Створюємо категорію для таргета
  let(:target) { Target.create!(category: category, name: "Lever", domain: "lever.co", allow_query_strings: true, is_active: true) }
  let(:prompt) { Prompt.create!(search: search, target: target, full_query_text: 'site:lever.co "ruby"', status: "pending") }
  let(:prompt_id) { prompt.id }
  let(:user_id) { user.id }

  let(:randomized_query) { "site:lever.co intitle:\"ruby\"" }
  let(:batch_data) { [{ "url" => "https://lever.co/1" }] }
  let(:collector_summary) { { success: true, failed_engines: [], error: nil } }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_render_to)
    allow(SearchCampaigns::LifecycleNotifier).to receive(:broadcast_status)
    allow(SearchCampaigns::DorkRandomizer).to receive(:perform).with(prompt.full_query_text).and_return(randomized_query)

    allow(SearchEngines::ResultsCollector).to receive(:call)
      .and_yield(batch_data, "SearchEngines::Yacy::RawResultsCollector")
      .and_return(collector_summary)

    allow(SearchCampaigns::ResultHandler).to receive(:call).and_return({ raw_count: 1, new_count: 1 })
    allow(Rails.logger).to receive(:error)
  end

  describe "#perform" do
    context "when prompt is not in pending status" do
      before do
        prompt.update!(status: "active")
      end

      it "returns early and does not process the prompt" do
        job.perform(prompt_id, user_id)

        expect(SearchEngines::ResultsCollector).not_to have_received(:call)
      end
    end

    context "when prompt is successfully locked to active" do
      it "fetches the prompt, randomizes the query, and triggers collector" do
        job.perform(prompt_id, user_id)

        expect(SearchCampaigns::DorkRandomizer).to have_received(:perform).with(prompt.full_query_text)
        expect(SearchEngines::ResultsCollector).to have_received(:call).with(
          randomized_query,
          time_range: "month",
          dynamic_url: true
        )
      end

      it "broadcasts initial scraping status via Turbo Streams" do
        job.perform(prompt_id, user_id)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_render_to).with(
          search, :results,
          template: "searches/update_status",
          assigns: { message: "[lever.co] Requesting data from Search Pipeline..." }
        )
      end

      context "with different handler outcomes" do
        it "broadcasts success message when new links are imported" do
          allow(SearchCampaigns::ResultHandler).to receive(:call).and_return({ raw_count: 5, new_count: 2 })

          job.perform(prompt_id, user_id)

          expect(Turbo::StreamsChannel).to have_received(:broadcast_render_to).with(
            search, :results,
            template: "searches/update_status",
            assigns: { message: "[lever.co] Extracted 5 links. Imported 2 NEW leads!" }
          )
        end

        it "broadcasts warning when links are extracted but all are duplicates" do
          allow(SearchCampaigns::ResultHandler).to receive(:call).and_return({ raw_count: 5, new_count: 0 })

          job.perform(prompt_id, user_id)

          expect(Turbo::StreamsChannel).to have_received(:broadcast_render_to).with(
            search, :results,
            template: "searches/update_status",
            assigns: { message: "[lever.co] Extracted 5 links, but all of them are already processed." }
          )
        end

        it "broadcasts specific message when engine error occurs" do
          allow(SearchCampaigns::ResultHandler).to receive(:call).and_return({ raw_count: 0, new_count: 0, error: "Timeout" })

          job.perform(prompt_id, user_id)

          expect(Turbo::StreamsChannel).to have_received(:broadcast_render_to).with(
            search, :results,
            template: "searches/update_status",
            assigns: { message: "[lever.co] Engine error: Timeout" }
          )
        end

        it "broadcasts zero results message when no URLs are found" do
          allow(SearchCampaigns::ResultHandler).to receive(:call).and_return({ raw_count: 0, new_count: 0 })

          job.perform(prompt_id, user_id)

          expect(Turbo::StreamsChannel).to have_received(:broadcast_render_to).with(
            search, :results,
            template: "searches/update_status",
            assigns: { message: "[lever.co] 0 valid URLs extracted (no matches or engines temporary blocked)." }
          )
        end
      end

      context "when an exception occurs during processing" do
        before do
          allow(SearchEngines::ResultsCollector).to receive(:call).and_raise(StandardError.new("Redis down"))
        end

        it "reverts the prompt status back to pending and reraises the exception" do
          expect { job.perform(prompt_id, user_id) }.to raise_error(StandardError, "Redis down")
          expect(prompt.reload.status).to eq("pending")
        end
      end

      context "when Turbo Streams broadcast fails" do
        before do
          allow(Turbo::StreamsChannel).to receive(:broadcast_render_to).and_raise(
            StandardError.new("Redis connection lost for WebSockets")
          )
        end

        it "safely catches the error, logs it, and continues executing the job" do
          expect { job.perform(prompt_id, user_id) }.not_to raise_error
          expect(Rails.logger).to have_received(:error).with(/Turbo broadcast failed/).at_least(:once)
          expect(SearchCampaigns::ResultHandler).to have_received(:call)
        end
      end
    end
  end
end
