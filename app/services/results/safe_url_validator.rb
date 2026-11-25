# frozen_string_literal: true

require "ipaddr"
require "uri"

module Results
  class SafeUrlValidator
    METADATA_IP = IPAddr.new("169.254.169.254").freeze

    # Do not resolve DNS on the host — Tor (socks5h) resolves hostnames remotely.
    def self.safe?(url_string)
      new(url_string).safe?
    end

    def initialize(url_string)
      @url_string = url_string
    end

    def safe?
      uri = URI.parse(@url_string)
      return false unless valid_scheme_and_host?(uri)
      return false if blocked_hostname?(uri.hostname)

      literal_ip = parse_literal_ip(uri.hostname)
      literal_ip.nil? || !private_or_restricted_ip?(literal_ip)
    rescue StandardError
      false
    end

    private

    def valid_scheme_and_host?(uri)
      %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.blank?
    end

    def blocked_hostname?(hostname)
      hostname.casecmp?("localhost") || hostname.end_with?(".localhost")
    end

    def parse_literal_ip(hostname)
      IPAddr.new(hostname)
    rescue IPAddr::InvalidAddressError
      nil
    end

    def private_or_restricted_ip?(ip)
      ip.loopback? || ip.private? || ip.link_local? || ip == METADATA_IP
    end
  end
end
