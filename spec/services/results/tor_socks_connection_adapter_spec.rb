# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::TorSocksConnectionAdapter, type: :adapter do
  let(:uri) { URI.parse("https://example.com/job_search") }
  let(:options) { { timeout: 5 } }
  let(:adapter) { described_class.new(uri, options) }

  let(:net_http_proxy_class) { class_double(Net::HTTP) }
  let(:http_instance) do
    instance_double(
      Net::HTTP,
      "use_ssl=": nil,
      "open_timeout=": nil,
      "read_timeout=": nil,
      "write_timeout=": nil,
      "max_retries=": nil,
      set_debug_output: nil,
      "ciphers=": nil,
      "local_host=": nil,
      "local_port=": nil
    )
  end

  before do
    allow(Net::HTTP).to receive(:socks_proxy).and_return(net_http_proxy_class)
    allow(net_http_proxy_class).to receive(:new).with("example.com", 443).and_return(http_instance)
    allow(adapter).to receive(:attach_ssl_certificates)
  end

  describe "#connection" do
    context "when TOR_PROXY_HOSTS and TOR_PROXY_PORT environment variables are omitted" do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("TOR_PROXY_HOSTS", "tor_1").and_return("tor_1")
        allow(ENV).to receive(:fetch).with("TOR_PROXY_PORT", "9050").and_return("9050")
      end

      it "falls back to default 'tor_1' host and port 9050" do
        expect(Net::HTTP).to receive(:socks_proxy).with("tor_1", 9050).and_return(net_http_proxy_class)

        connection = adapter.connection
        expect(connection).to eq(http_instance)
      end
    end

    context "when TOR_PROXY_HOSTS contains a comma-separated list of proxies" do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("TOR_PROXY_HOSTS", "tor_1").and_return("tor_1, tor_2, tor_3")
        allow(ENV).to receive(:fetch).with("TOR_PROXY_PORT", "9050").and_return("9050")
      end

      it "splits the string and picks one of the hosts randomly using .sample" do
        allowed_hosts = %w[tor_1 tor_2 tor_3]

        expect(Net::HTTP).to receive(:socks_proxy) do |host, port|
          expect(allowed_hosts).to include(host)
          expect(port).to eq(9050)
          net_http_proxy_class
        end

        adapter.connection
      end
    end

    context "when custom TOR_PROXY_PORT is provided" do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("TOR_PROXY_HOSTS", "tor_1").and_return("tor_custom_node")
        allow(ENV).to receive(:fetch).with("TOR_PROXY_PORT", "9050").and_return("9150")
      end

      it "converts port to integer and passes it to socks_proxy" do
        expect(Net::HTTP).to receive(:socks_proxy).with("tor_custom_node", 9150).and_return(net_http_proxy_class)

        adapter.connection
      end
    end

    context "when URL scheme is HTTP (non-SSL)" do
      let(:uri) { URI.parse("http://example.com/path") }

      before do
        allow(Net::HTTP).to receive(:socks_proxy).and_return(net_http_proxy_class)
        allow(net_http_proxy_class).to receive(:new).with("example.com", 80).and_return(http_instance)
      end

      it "configures use_ssl as false and port as 80" do
        expect(http_instance).to receive(:use_ssl=).with(false)

        adapter.connection
      end
    end

    context "when advanced options (timeouts, retries, ciphers, local binding, debug) are provided" do
      let(:options) do
        {
          timeout: 12,
          read_timeout: 15,
          open_timeout: 3,
          write_timeout: 4,
          max_retries: 3,
          ciphers: "HIGH:!aNULL",
          local_host: "127.0.0.1",
          local_port: 54_321,
          debug_output: $stdout
        }
      end

      it "applies all timeouts, retry policies, and low-level socket options correctly" do
        expect(http_instance).to receive(:open_timeout=).with(12)
        expect(http_instance).to receive(:read_timeout=).with(12)
        expect(http_instance).to receive(:write_timeout=).with(12)
        expect(http_instance).to receive(:read_timeout=).with(15)
        expect(http_instance).to receive(:open_timeout=).with(3)
        expect(http_instance).to receive(:write_timeout=).with(4)
        expect(http_instance).to receive(:max_retries=).with(3)
        expect(http_instance).to receive(:set_debug_output).with($stdout)
        expect(http_instance).to receive(:ciphers=).with("HIGH:!aNULL")
        expect(http_instance).to receive(:local_host=).with("127.0.0.1")
        expect(http_instance).to receive(:local_port=).with(54_321)

        adapter.connection
      end
    end
  end
end
