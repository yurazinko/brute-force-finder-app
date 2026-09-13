# frozen_string_literal: true

class SearxngUpdaterJob < BaseContainerUpdaterJob
  CONTAINER_COUNT = ENV.fetch("SEARXNG_URLS", "http://searxng_1:8080").split(",").size
  SEARXNG_IMAGE = ENV.fetch("SEARXNG_IMAGE", "searxng/searxng:latest")

  private

  def image_name
    SEARXNG_IMAGE
  end

  def containers_to_update
    (1..CONTAINER_COUNT).map do |index|
      {
        service: "searxng_#{index}",
        container_name: "finder_searxng_#{index}",
        index: index
      }
    end
  end

  def run_smoke_test(info)
    service_host = info[:service]
    url = URI("http://#{service_host}:8080/search?q=test&format=json")

    response = Net::HTTP.get_response(url)
    raise "Smoke test failed with status code #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    json = JSON.parse(response.body)
    raise "Smoke test payload missing 'results' key" unless json.key?("results")
  rescue StandardError => e
    raise "Smoke test failed for #{service_host}: #{e.message}"
  end
end
