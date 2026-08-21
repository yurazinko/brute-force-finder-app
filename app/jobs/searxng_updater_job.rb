# frozen_string_literal: true

require "open3"
require "net/http"
require "json"
require "uri"
require "socket"

class SearxngUpdaterJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 0

  CONTAINER_COUNT = ENV.fetch("SEARXNG_URLS", "http://searxng_1:8080").split(",").size
  PROJECT_NAME = ENV.fetch("COMPOSE_PROJECT_NAME", "brute-force-finder-app")
  SEARXNG_IMAGE = ENV.fetch("SEARXNG_IMAGE", "searxng/searxng:latest")

  def perform
    pull_latest_image

    (1..CONTAINER_COUNT).each do |index|
      process_container_update(index)
    end
  end

  private

  def pull_latest_image
    logger.info "[SearxngUpdaterJob] Pulling latest image: #{SEARXNG_IMAGE}"
    success = system("docker", "pull", SEARXNG_IMAGE)

    raise "Failed to pull image #{SEARXNG_IMAGE}" unless success
  end

  def process_container_update(index)
    container_service = "searxng_#{index}"
    container_name = "finder_searxng_#{index}"

    logger.info "[SearxngUpdaterJob] Updating #{container_service} via Docker Compose (path: #{host_project_path})..."

    unless recreate_container(container_service)
      raise "Failed to execute docker compose recreate for #{container_service}"
    end

    begin
      wait_for_healthy_status(container_name)
      run_smoke_test(index)
      logger.info "[SearxngUpdaterJob] Successfully updated and verified #{container_service}"
    rescue StandardError => e
      logger.error "[SearxngUpdaterJob] #{container_service} update failed: #{e.message}"
      raise e
    end
  end

  def recreate_container(container_service)
    local_compose_file = Rails.root.join("docker-compose.yml").to_s

    system(
      { "PWD" => host_project_path },
      "docker", "compose",
      "-p", PROJECT_NAME,
      "-f", local_compose_file,
      "--project-directory", host_project_path,
      "up", "-d",
      "--no-deps",
      "--force-recreate",
      "--remove-orphans",
      container_service
    )
  end

  def wait_for_healthy_status(container_name)
    max_attempts = 30

    max_attempts.times do
      sleep 3

      status = capture_cmd(
        "docker", "inspect",
        "--format", "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}",
        container_name
      ).strip

      return if status == "healthy"
    end

    logs = capture_cmd("docker", "logs", "--tail", "20", container_name)
    last_status = capture_cmd("docker", "inspect", "--format", "{{.State.Health.Status}}", container_name).strip

    raise "Container #{container_name} failed healthcheck (status: '#{last_status}'). Logs:\n#{logs}"
  end

  def run_smoke_test(index)
    service_host = "searxng_#{index}"
    url = URI("http://#{service_host}:8080/search?q=test&format=json")

    response = Net::HTTP.get_response(url)
    raise "Smoke test failed with status code #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    json = JSON.parse(response.body)
    raise "Smoke test payload missing 'results' key" unless json.key?("results")
  rescue StandardError => e
    raise "Smoke test failed for #{service_host}: #{e.message}"
  end

  def host_project_path
    @host_project_path ||= begin
      hostname = Socket.gethostname
      stdout = capture_cmd(
        "docker", "inspect",
        "--format", '{{range .Mounts}}{{if eq .Destination "/app"}}{{.Source}}{{end}}{{end}}',
        hostname
      ).strip

      stdout.empty? ? "." : stdout
    end
  end

  def capture_cmd(*args)
    stdout, _status = Open3.capture2e(*args)
    stdout
  rescue StandardError => e
    logger.error "[SearxngUpdaterJob] Command execution error #{args.join(' ')}: #{e.message}"
    ""
  end
end
