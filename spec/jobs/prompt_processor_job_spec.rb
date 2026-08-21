# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptProcessorJob, type: :job do
  let(:job) { described_class.new }
  let(:prompt_id) { 42 }
  let(:user_id) { 1 }
  let(:full_query) { "site:lever.co \"ruby\"" }

  let(:search_mock) { instance_double("Search", time_frame: "month") }
  let(:prompt_mock) do
    instance_double(
      "Prompt",
      id: prompt_id,
      full_query_text: full_query,
      search: search_mock
    )
  end

  let(:randomized_query) { "site:lever.co intitle:\"ruby\"" }
  let(:collector_result) { { success: true, data: [{ "url" => "https://lever.co/1" }], failed_engines: [] } }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_render_to)
    allow(SearchCampaigns::DorkRandomizer).to receive(:perform).with(full_query).and_return(randomized_query)

    allow(SearchEngines::ResultsCollector).to receive(:call).and_return(collector_result)

    allow(SearchCampaigns::ResultHandler).to receive(:call).and_return({ raw_count: 1, new_count: 1 })
    allow(Prompt).to receive(:find).with(prompt_id).and_return(prompt_mock)
    allow(Rails.logger).to receive(:error)
  end

  describe "#perform" do
    context "when prompt is not in pending status" do
      before do
        allow(Prompt).to receive(:where).with(id: prompt_id, status: "pending").and_return(
          double(update_all: 0)
        )
      end

      it "returns early and does not process the prompt" do
        job.perform(prompt_id, user_id)

        expect(Prompt).not_to have_received(:find)
        expect(SearchEngines::ResultsCollector).not_to have_received(:call)
      end
    end

    context "when prompt is successfully locked to active" do
      before do
        allow(Prompt).to receive(:where).with(id: prompt_id, status: "pending").and_return(
          double(update_all: 1)
        )
      end

      it "fetches the prompt, randomizes the query, and triggers collector" do
        job.perform(prompt_id, user_id)

        expect(SearchCampaigns::DorkRandomizer).to have_received(:perform).with(full_query)
        expect(SearchEngines::ResultsCollector).to have_received(:call).with(
          randomized_query,
          time_range: "month"
        )
      end

      it "broadcasts initial scraping status via Turbo Streams" do
        job.perform(prompt_id, user_id)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_render_to).with(
          search_mock, :results,
          template: "searches/update_status",
          assigns: { message: "[lever.co] Requesting data from Search Pipeline..." }
        )
      end

      context "with different handler outcomes" do
        it "broadcasts success message when new links are imported" do
          allow(SearchCampaigns::ResultHandler).to receive(:call).and_return({ raw_count: 5, new_count: 2 })

          job.perform(prompt_id, user_id)

          expect(Turbo::StreamsChannel).to have_received(:broadcast_render_to).with(
            search_mock, :results,
            template: "searches/update_status",
            assigns: { message: "[lever.co] Extracted 5 links. Imported 2 NEW leads!" }
          )
        end

        it "broadcasts warning when links are extracted but all are duplicates" do
          allow(SearchCampaigns::ResultHandler).to receive(:call).and_return({ raw_count: 5, new_count: 0 })

          job.perform(prompt_id, user_id)

          expect(Turbo::StreamsChannel).to have_received(:broadcast_render_to).with(
            search_mock, :results,
            template: "searches/update_status",
            assigns: { message: "[lever.co] Extracted 5 links, but all of them are already processed." }
          )
        end

        it "broadcasts specific message when engine error occurs" do
          allow(SearchCampaigns::ResultHandler).to receive(:call).and_return({ error: "Timeout" })

          job.perform(prompt_id, user_id)

          expect(Turbo::StreamsChannel).to have_received(:broadcast_render_to).with(
            search_mock, :results,
            template: "searches/update_status",
            assigns: { message: "[lever.co] Engine error: Timeout" }
          )
        end

        it "broadcasts zero results message when no URLs are found" do
          allow(SearchCampaigns::ResultHandler).to receive(:call).and_return({ raw_count: 0, new_count: 0 })

          job.perform(prompt_id, user_id)

          expect(Turbo::StreamsChannel).to have_received(:broadcast_render_to).with(
            search_mock, :results,
            template: "searches/update_status",
            assigns: { message: "[lever.co] 0 valid URLs extracted (no matches or engines temporary blocked)." }
          )
        end
      end

      context "when an exception occurs during processing" do
        let(:prompt_relation_mock) { double }

        before do
          allow(Prompt).to receive(:where).with(id: prompt_id).and_return(prompt_relation_mock)
          allow(prompt_relation_mock).to receive(:update_all)

          allow(SearchEngines::ResultsCollector).to receive(:call).and_raise(StandardError.new("Redis down"))
        end

        it "reverts the prompt status back to pending and reraises the exception" do
          expect { job.perform(prompt_id, user_id) }.to raise_error(StandardError, "Redis down")
          expect(prompt_relation_mock).to have_received(:update_all).with(status: "pending")
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
