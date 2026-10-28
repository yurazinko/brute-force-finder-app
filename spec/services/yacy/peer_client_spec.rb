# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchEngines::Yacy::Api::PeerClient, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:query) { 'site:https://example.com/some/path "ruby developer"' }
  let(:options) { {} }
  let(:urls_env) { "http://yacy-peer-1.local:8090,http://yacy-peer-2.local:8090" }
  let(:instance1) { "http://yacy-peer-1.local:8090" }
  let(:instance2) { "http://yacy-peer-2.local:8090" }

  let(:redis) { Redis.new(url: ENV.fetch("REDIS_URL", "redis://redis:6379/1")) }

  before do
    allow(Redis).to receive(:new).and_return(redis)
    redis.flushdb

    stub_const("ENV", ENV.to_h.merge("YACY_PEER_URLS" => urls_env))
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:info)
  end

  after do
    redis.flushdb
  end

  describe ".search" do
    it "instantiates the client and calls execute" do
      client_instance = instance_double(described_class, execute: { success: true, data: [] })
      allow(described_class).to receive(:new).with(query, options).and_return(client_instance)

      described_class.search(query, options)

      expect(client_instance).to have_received(:execute)
    end
  end

  describe "pool initialization (initialize_pool)" do
    it "populates the Redis list with values from ENV['YACY_PEER_URLS']" do
      described_class.new(query, options)

      expect(redis.llen("yacy:peers_pool")).to eq(2)
      expect(redis.lrange("yacy:peers_pool", 0, -1)).to contain_exactly(instance1, instance2)
      expect(redis.exists?("yacy:peers_pool:synced")).to be_truthy
    end

    context "when ENV['YACY_PEER_URLS'] is not set" do
      before do
        stub_const("ENV", ENV.to_h.except("YACY_PEER_URLS"))
      end

      it "falls back to localhost" do
        described_class.new(query, options)

        expect(redis.llen("yacy:peers_pool")).to eq(1)
        expect(redis.lrange("yacy:peers_pool", 0, -1)).to eq(["http://localhost:8090"])
      end
    end
  end

  describe "#build_formatted_query" do
    it "normalizes HTML quotes and extracts clean host for 'site:' operator" do
      client = described_class.new(query, options)
      formatted = client.send(:build_formatted_query)

      expect(formatted).to eq('site:example.com "ruby developer"')
    end

    context "when time_range option is provided" do
      let(:options) { { time_range: "week" } }

      it "appends date filter based on time frame" do
        travel_to Time.zone.local(2026, 8, 21) do
          client = described_class.new(query, options)
          formatted = client.send(:build_formatted_query)
          expect(formatted).to eq('site:example.com "ruby developer" from:2026/08/14')
        end
      end
    end
  end

  describe "#perform_request" do
    let(:client) { described_class.new(query, options) }

    context "when the request is successful (HTTP 200)" do
      let(:yacy_response_body) do
        {
          "channels" => [
            {
              "items" => [
                {
                  "link" => "https://example.com/job/1",
                  "title" => "Ruby Lead",
                  "description" => "Looking for Ruby developer",
                  "engine" => "YaCy"
                }
              ]
            }
          ]
        }.to_json
      end

      before do
        stub_request(:get, "#{instance1}/yacysearch.json")
          .with(query: hash_including(query: 'site:example.com "ruby developer"'))
          .to_return(status: 200, body: yacy_response_body)
      end

      it "returns formatted result payload" do
        result = client.send(:perform_request, instance1)

        expect(result).to eq(
          success: true,
          data: [
            {
              url: "https://example.com/job/1",
              title: "Ruby Lead",
              content: "Looking for Ruby developer",
              engine: "YaCy"
            }
          ],
          failed_engines: []
        )
      end
    end

    context "when YaCy returns an HTTP error (e.g., 500)" do
      before do
        stub_request(:get, %r{#{instance1}/yacysearch\.json})
          .to_return(status: 500)
      end

      it "returns error hash and marks instance as dead" do
        result = client.send(:perform_request, instance1)

        expect(result).to eq(success: false, error: "HTTP 500")
        expect(redis.exists?("yacy:dead:#{instance1}")).to be_truthy
      end
    end

    context "when an exception occurs during HTTP request (Network/Timeout failure)" do
      before do
        stub_request(:get, %r{#{instance1}/yacysearch\.json})
          .to_raise(StandardError.new("Connection refused"))
      end

      it "marks instance as dead in Redis, logs warning, and returns error" do
        result = client.send(:perform_request, instance1)

        expect(result).to eq(success: false, error: "Connection refused")
        expect(redis.exists?("yacy:dead:#{instance1}")).to be_truthy
        expect(Rails.logger).to have_received(:warn).with(
          "[Yacy::Api::PeerClient] YaCy instance #{instance1} failed: Connection refused"
        )
      end
    end
  end
end
