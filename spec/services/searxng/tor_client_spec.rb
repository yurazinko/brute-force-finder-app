# frozen_string_literal: true

require "rails_helper"

RSpec.describe Searxng::TorClient, type: :service do
  let(:query) { 'site:lever.co "ruby"' }

  let(:base_url) { "http://searxng_1:8080" }
  let(:search_endpoint) { "#{base_url}/search" }

  before do
    allow_any_instance_of(described_class).to receive(:sleep)
    stub_const("ENV", ENV.to_h.merge("SEARXNG_URLS" => base_url))
  end

  describe ".search" do
    it "instantiates the client and calls execute" do
      client_instance = instance_double(described_class, execute: [])
      allow(described_class).to receive(:new).with(query, {}).and_return(client_instance)

      described_class.search(query)

      expect(client_instance).to have_received(:execute)
    end
  end

  describe "#execute" do
    context "when query is blank" do
      it "returns an empty array immediately without making an HTTP request" do
        client = described_class.new("   ")

        expect(client.execute).to eq({ data: [], success: true })
        expect(WebMock).not_to have_requested(:get, /.*/)
      end
    end

    context "when the request is successful (status 200)" do
      let(:mock_response_body) do
        {
          "results" => [
            { "url" => "https://lever.co/job1", "title" => "Ruby Developer" },
            { "url" => "https://lever.co/job2", "title" => "Senior RoR Engineer" },
            { "url" => "https://lever.co/job1", "title" => "Ruby Developer" }
          ]
        }.to_json
      end

      before do
        stub_request(:get, search_endpoint)
          .with(query: hash_including(q: query))
          .to_return(
            status: 200,
            body: mock_response_body,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns unique urls and titles parsed directly from WebMock body" do
        expected_result = {
          data: [
            { "url" => "https://lever.co/job1", "title" => "Ruby Developer" },
            { "url" => "https://lever.co/job2", "title" => "Senior RoR Engineer" }
          ],
          failed_engines: [],
          success: true
        }

        expect(described_class.new(query).execute).to eq(expected_result)
      end
    end

    context "when access is forbidden (status 403)" do
      before do
        stub_request(:get, search_endpoint).with(query: hash_including(q: query)).to_return(status: 403)
        allow(Rails.logger).to receive(:error)
      end

      it "logs a specific error message and returns an empty array" do
        expect(described_class.new(query).execute).to eq({ error: "SearXNG returned HTTP 403", success: false })
      end
    end

    context "when server returns an unexpected status code (e.g. 500)" do
      before do
        stub_request(:get, search_endpoint).with(query: hash_including(q: query)).to_return(status: 500)
        allow(Rails.logger).to receive(:error)
      end

      it "logs the unexpected status code and returns an empty array" do
        expect(described_class.new(query).execute).to eq({ error: "SearXNG returned HTTP 500", success: false })
      end
    end

    context "when a network failure occurs (Timeout/Connection Refused)" do
      before do
        stub_request(:get, search_endpoint)
          .with(query: hash_including(q: query))
          .to_raise(Timeout::Error.new("Execution expired"))

        allow(Rails.logger).to receive(:error)
      end

      it "rescues Timeout::Error, logs it, and returns a specific gateway timeout message" do
        expect(described_class.new(query).execute).to eq({ error: "SearXNG gateway timeout", success: false })
        expect(Rails.logger).to have_received(:error).with("[Searxng::TorClient] SearXNG gateway timeout")
      end
    end

    context "when JSON parsing fails" do
      before do
        stub_request(:get, search_endpoint)
          .with(query: hash_including(q: query))
          .to_return(status: 200, body: "invalid-json{", headers: { "Content-Type" => "application/json" })

        allow(Rails.logger).to receive(:error)
      end

      it "rescues JSON::ParserError, logs it, and returns an empty array" do
        expect(described_class.new(query).execute).to eq(
          { error: "Malformed JSON response (Engine blocked or bad proxy config)", success: false }
        )
        expect(Rails.logger).to have_received(:error).with(/Malformed JSON response/)
      end
    end
  end
end
