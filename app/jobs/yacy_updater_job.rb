# frozen_string_literal: true

class YacyUpdaterJob < BaseContainerUpdaterJob
  YACY_IMAGE = ENV.fetch("YACY_IMAGE", "yacy/yacy_search_server:latest-alpine")

  private

  def image_name
    YACY_IMAGE
  end

  def containers_to_update
    [
      {
        service: "yacy",
        container_name: "finder_yacy"
      }
    ]
  end

  def run_smoke_test(info) # rubocop:disable Metrics/MethodLength
    service_host = info[:service]
    url = URI("http://#{service_host}:8090/yacysearch.json?query=test")

    max_retries = 10

    found = false
    max_retries.times do |attempt|
      begin
        response = Net::HTTP.get_response(url)
        if response.is_a?(Net::HTTPSuccess)
          json = JSON.parse(response.body)
          if json.key?("channels")
            found = true
            break
          end
        end
      end

      logger.info "[YacyUpdaterJob] Waiting for HTTP server on #{service_host} (#{attempt + 1}/#{max_retries})..."
      sleep 5
    end

    return if found

    raise "Smoke test failed for #{service_host}: HTTP server was not ready after #{max_retries * 5} seconds"
  end
end
