# frozen_string_literal: true

require "rails_helper"

RSpec.describe Searxng::TorClient, type: :service do
  let(:query) { 'site:lever.co "ruby"' }
  let(:base_url) { ENV.fetch("SEARXNG_URL", "http://localhost:8080") }
  let(:search_endpoint) { "#{base_url}/search" }

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

        expect(client.execute).to eq([])
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
        expected_result = [
          { "url" => "https://lever.co/job1", "title" => "Ruby Developer" },
          { "url" => "https://lever.co/job2", "title" => "Senior RoR Engineer" }
        ]

        expect(described_class.new(query).execute).to eq(expected_result)
      end
    end

    context "when access is forbidden (status 403)" do
      before do
        stub_request(:get, search_endpoint).with(query: hash_including(q: query)).to_return(status: 403)
        allow(Rails.logger).to receive(:error)
      end

      it "logs an specific error message and returns an empty array" do
        expect(described_class.new(query).execute).to eq([])
        expect(Rails.logger).to have_received(:error).with(/Unexpected status code 403/)
      end
    end

    context "when server returns an unexpected status code (e.g. 500)" do
      before do
        stub_request(:get, search_endpoint).with(query: hash_including(q: query)).to_return(status: 500)
        allow(Rails.logger).to receive(:error)
      end

      it "logs the unexpected status code and returns an empty array" do
        expect(described_class.new(query).execute).to eq([])
        expect(Rails.logger).to have_received(:error).with(/Unexpected status code 500/)
      end
    end

    context "when a network failure occurs (Timeout/Connection Refused)" do
      before do
        stub_request(:get, search_endpoint)
          .with(query: hash_including(q: query))
          .to_raise(Net::OpenTimeout.new("Execution expired"))

        allow(Rails.logger).to receive(:error)
      end

      it "rescues StandardError, logs it, and returns an empty array" do
        expect(described_class.new(query).execute).to eq([])
        expect(Rails.logger).to have_received(:error).with(/Error: Execution expired/)
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
        expect(described_class.new(query).execute).to eq([])
        expect(Rails.logger).to have_received(:error).with(/Failed to parse JSON response/)
      end
    end
  end
end
