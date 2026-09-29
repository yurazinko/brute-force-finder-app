# frozen_string_literal: true

class FourgetUpdaterJob < BaseContainerUpdaterJob
  FOURGET_IMAGE = ENV.fetch("FOURGET_IMAGE", "luuul/4get:latest")

  private

  def image_name
    FOURGET_IMAGE
  end

  def containers_to_update
    [
      {
        service: "fourget",
        container_name: "finder_4get"
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
    url = URI("http://#{service_host}:80/api/v1/web?s=test")

    req = Net::HTTP::Get.new(url)
    req["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0 Safari/537.36"
    req["Accept"] = "application/json"

    Net::HTTP.start(url.hostname, url.port, open_timeout: 5, read_timeout: 10) do |http|
      http.request(req)
    end
  end

  def validate_response!(response)
    raise "Smoke test failed with HTTP code #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    json = JSON.parse(response.body)
    raise "Smoke test failed: status is not 'ok' (#{json['status']})" unless json["status"] == "ok"
    raise "Smoke test payload missing 'web' key" unless json.key?("web")
  end
end
