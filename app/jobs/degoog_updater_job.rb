# frozen_string_literal: true

class DegoogUpdaterJob < BaseContainerUpdaterJob
  DEGOOG_IMAGE = ENV.fetch("DEGOOG_IMAGE", "ghcr.io/degoog-org/degoog:latest")

  private

  def image_name
    DEGOOG_IMAGE
  end

  def containers_to_update
    [
      {
        service: "degoog",
        container_name: "finder_degoog"
      }
    ]
  end

  def run_smoke_test(info)
    service_host = info[:service]
    response = fetch_smoke_test_response(service_host)
    validate_response!(response)
  rescue StandardError => e
    raise "Smoke test failed for #{service_host}: #{e.message}"
  end

  def fetch_smoke_test_response(service_host)
    # Зверніть увагу на порт 4444
    url = URI("http://#{service_host}:4444/search?q=test")

    req = Net::HTTP::Get.new(url)
    req["Accept"] = "application/json"

    Net::HTTP.start(url.hostname, url.port, open_timeout: 5, read_timeout: 10) do |http|
      http.request(req)
    end
  end

  def validate_response!(response)
    raise "Smoke test failed with HTTP code #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  end
end
