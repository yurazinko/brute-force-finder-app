# frozen_string_literal: true

require "socksify/http"

module Results
  class TorSocksConnectionAdapter < HTTParty::ConnectionAdapter
    TIMEOUT_KEYS = %i[open_timeout read_timeout write_timeout].freeze

    ADVANCED_SETTERS = {
      max_retries: :max_retries=,
      ciphers: :ciphers=,
      local_host: :local_host=,
      local_port: :local_port=,
      debug_output: :set_debug_output
    }.freeze

    def connection
      http = build_http_connection
      http.use_ssl = uri.port == 443 || uri.scheme == "https"
      attach_ssl_certificates(http, options)
      configure_timeouts(http)
      configure_advanced_options(http)

      http
    end

    private

    def build_http_connection
      host = clean_host(uri.host)
      port = uri.port || (uri.scheme == "https" ? 443 : 80)

      proxy_hosts = ENV.fetch("TOR_PROXY_HOSTS", "tor_1").split(",")
      proxy_host = proxy_hosts.sample.strip
      proxy_port = Integer(ENV.fetch("TOR_PROXY_PORT", "9050"))

      Net::HTTP.socks_proxy(proxy_host, proxy_port).new(host, port)
    end

    def configure_timeouts(http)
      TIMEOUT_KEYS.each { |key| http.send("#{key}=", options[:timeout]) } if add_timeout?(options[:timeout])

      TIMEOUT_KEYS.each do |key|
        val = options[key]
        http.send("#{key}=", val) if add_timeout?(val)
      end
    end

    def configure_advanced_options(http)
      ADVANCED_SETTERS.each do |key, setter|
        val = options[key]
        next unless val

        next if key == :max_retries && !add_max_retries?(val)

        http.send(setter, val)
      end
    end
  end
end
