# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchEngines::Yacy::Api::PeerClient do
  include ActiveSupport::Testing::TimeHelpers

  subject(:client) { described_class.new(query, options) }

  let(:query) { 'site:https://example.com/some/path "ruby developer"' }
  let(:options) { {} }
  let(:redis_mock) { instance_double(Redis) }

  before do
    allow(Redis).to receive(:new).and_return(redis_mock)
    allow(redis_mock).to receive(:exists?).and_return(true)
    allow(redis_mock).to receive(:rpoplpush).and_return("http://yacy-peer-1.local:8090")
    allow(redis_mock).to receive(:rpush)
    allow(redis_mock).to receive(:setex)
  end

  describe "pool initialization (initialize_pool)" do
    context "when the pool key does not exist in Redis" do
      before do
        allow(redis_mock).to receive(:exists?).with(described_class::YACY_POOL_KEY).and_return(false)
      end

      it "populates the Redis list with values from ENV['YACY_PEER_URLS']" do
        stub_const("ENV", ENV.to_hash.merge("YACY_PEER_URLS" => "http://peer1:8090,http://peer2:8090"))

        client # Instantiation triggers initialize_pool

        expect(redis_mock).to have_received(:rpush).with(
          described_class::YACY_POOL_KEY,
          array_including("http://peer1:8090", "http://peer2:8090")
        )
      end

      it "falls back to localhost when ENV is not set" do
        stub_const("ENV", ENV.to_hash.except("YACY_PEER_URLS"))

        client

        expect(redis_mock).to have_received(:rpush).with(
          described_class::YACY_POOL_KEY,
          ["http://localhost:8090"]
        )
      end
    end

    context "when the pool already exists in Redis" do
      before do
        allow(redis_mock).to receive(:exists?).with(described_class::YACY_POOL_KEY).and_return(true)
      end

      it "does not overwrite data in Redis" do
        client

        expect(redis_mock).not_to have_received(:rpush)
      end
    end
  end

  describe "instance rotation (next_available_instance)" do
    it "rotates elements in the Redis list using rpoplpush" do
      allow(redis_mock).to receive(:rpoplpush)
        .with(described_class::YACY_POOL_KEY, described_class::YACY_POOL_KEY)
        .and_return("http://yacy-peer-2.local:8090")

      instance = client.send(:next_available_instance)

      expect(instance).to eq("http://yacy-peer-2.local:8090")
      expect(redis_mock).to have_received(:rpoplpush).with(
        described_class::YACY_POOL_KEY,
        described_class::YACY_POOL_KEY
      )
    end
  end

  describe "#build_formatted_query" do
    it "normalizes HTML quotes and extracts clean host for 'site:' operator" do
      formatted = client.send(:build_formatted_query)

      expect(formatted).to eq('site:example.com "ruby developer"')
    end

    context "when time_range option is provided" do
      let(:options) { { time_range: "week" } }

      it "appends date filter /date based on time frame" do
        travel_to Time.zone.local(2026, 8, 21) do
          formatted = client.send(:build_formatted_query)
          expect(formatted).to eq('site:example.com "ruby developer" from:2026/08/14 /date')
        end
      end
    end
  end

  describe "#perform_request" do
    let(:target_instance) { "http://yacy-peer-1.local:8090" }

    context "when the request is successful (HTTP 200)" do
      let(:yacy_response_body) do
        {
          "channels" => [
            {
              "items" => [
                {
                  "link" => "https://example.com/job/1",
                  "title" => "Ruby Lead",
                  "description" => "Looking for Ruby developer"
                }
              ]
            }
          ]
        }.to_json
      end

      let(:response_double) do
        instance_double(HTTParty::Response, code: 200, body: yacy_response_body)
      end

      before do
        allow(described_class).to receive(:get).and_return(response_double)
      end

      it "returns formatted result payload" do
        result = client.send(:perform_request, target_instance)

        expect(result).to eq(
          success: true,
          data: [
            {
              "url" => "https://example.com/job/1",
              "title" => "Ruby Lead",
              "content" => "Looking for Ruby developer"
            }
          ],
          failed_engines: []
        )
      end

      it "sends properly formatted query params" do
        client.send(:perform_request, target_instance)

        expect(described_class).to have_received(:get).with(
          "#{target_instance}/yacysearch.json",
          {
            timeout: 12,
            query: {
              query: 'site:example.com "ruby developer"',
              maximumRecords: 60,
              resource: "global",
              meanCount: 0,
              maximumTime: 10,
              verify: "ifexist",
              strictContentDom: false
            }
          }
        )
      end
    end

    context "when YaCy returns an HTTP error (e.g., 500)" do
      let(:response_double) { instance_double(HTTParty::Response, code: 500) }

      before do
        allow(described_class).to receive(:get).and_return(response_double)
      end

      it "returns error hash" do
        result = client.send(:perform_request, target_instance)

        expect(result).to eq(success: false, error: "HTTP 500")
      end
    end

    context "when an exception occurs during HTTP request (Network/Timeout failure)" do
      before do
        allow(described_class).to receive(:get).and_raise(StandardError.new("Connection refused"))
        allow(Rails.logger).to receive(:warn)
      end

      it "marks instance as dead in Redis and returns error" do
        result = client.send(:perform_request, target_instance)

        expect(result).to eq(success: false, error: "Connection refused")
        expect(redis_mock).to have_received(:setex).with(
          "#{described_class::REDIS_DEAD_PREFIX}#{target_instance}",
          anything,
          "dead"
        )
        expect(Rails.logger).to have_received(:warn).with(
          "[Yacy::Api::PeerClient] YaCy instance #{target_instance} failed: Connection refused"
        )
      end
    end
  end
end
