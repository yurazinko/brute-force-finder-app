# frozen_string_literal: true

class YacyUpdaterJob < BaseContainerUpdaterJob
  YACY_IMAGE = ENV.fetch("YACY_IMAGE", "yacy/yacy_search_server:latest-alpine")

  protected

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

  def run_smoke_test(info)
    service_host = info[:service]
    url = URI("http://#{service_host}:8090/yacysearch.json?query=test")

    response = Net::HTTP.get_response(url)
    raise "Smoke test failed with status code #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    json = JSON.parse(response.body)
    raise "Smoke test payload missing 'channels' key" unless json.key?("channels")
  rescue StandardError => e
    raise "Smoke test failed for #{service_host}: #{e.message}"
  end
end
