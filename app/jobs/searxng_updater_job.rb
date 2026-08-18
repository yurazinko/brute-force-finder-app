# frozen_string_literal: true

require "fileutils"
require "open3"
require "net/http"
require "json"
require "uri"

class SearxngUpdaterJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 0

  CONTAINER_COUNT = 5
  WORKING_DIR = "/app"
  PROJECT_NAME = ENV.fetch("COMPOSE_PROJECT_NAME", "brute-force-finder-app")
  SEARXNG_IMAGE = ENV.fetch("SEARXNG_IMAGE", "searxng/searxng:latest")

  LIMITER_CONFIG = <<~TOML
    [botdetection]
    ipv4_prefix = 32
    ipv6_prefix = 48
    trusted_proxies = []

    [botdetection.ip_lists]
    block_ip = []
    pass_ip = [
      "127.0.0.1",
      "::1",
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16"
    ]
    pass_searxng_org = true

    [botdetection.ip_limit]
    filter_link_local = false
    link_token = false
  TOML

  def perform
    ensure_limiter_configs!
    pull_latest_image

    (1..CONTAINER_COUNT).each do |index|
      process_container_update(index)
    end
  end

  private

  def ensure_limiter_configs!
    (1..CONTAINER_COUNT).each do |index|
      dir_path = File.join(WORKING_DIR, "searxng", "searxng_#{index}")
      file_path = File.join(dir_path, "limiter.toml")

      logger.info "[SearxngUpdaterJob] Ensuring limiter config at: #{file_path}"

      # Якщо Docker раніше створив папку замість файла — видаляємо її!
      FileUtils.rm_rf(file_path) if File.directory?(file_path)

      FileUtils.mkdir_p(dir_path)
      File.write(file_path, LIMITER_CONFIG)

      stat = File.stat(file_path)
      raise "#{file_path} is not a regular file after write operation!" unless stat.file?
    end

    logger.info "[SearxngUpdaterJob] All limiter.toml files verified successfully"
  end

  def pull_latest_image
    logger.info "[SearxngUpdaterJob] Pulling latest image: #{SEARXNG_IMAGE}"
    success = system("docker", "pull", SEARXNG_IMAGE)

    raise "Failed to pull image #{SEARXNG_IMAGE}" unless success
  end

  def process_container_update(index)
    container_service = "searxng_#{index}"
    container_name = "finder_searxng_#{index}"

    old_image_id = current_image_id(container_name)
    logger.info "[SearxngUpdaterJob] Updating #{container_service} (old image SHA: #{old_image_id})"

    unless recreate_container(container_service)
      raise "Failed to execute docker compose recreate for #{container_service}"
    end

    begin
      wait_for_healthy_status(container_name)
      run_smoke_test(index)
      logger.info "[SearxngUpdaterJob] Successfully updated and verified #{container_service}"
    rescue StandardError => e
      logger.error "[SearxngUpdaterJob] #{container_service} update failed: #{e.message}. Attempting rollback..."
      rollback_container(container_service, container_name, old_image_id)
      raise e
    end
  end

  def recreate_container(container_service)
    system(
      "docker", "compose",
      "-p", PROJECT_NAME,
      "--project-directory", WORKING_DIR,
      "up", "-d",
      "--no-deps",
      "--force-recreate",
      container_service
    )
  end

  def wait_for_healthy_status(container_name)
    max_attempts = 30 # 30 * 3 сек = 90 секунд

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

  def rollback_container(container_service, container_name, old_image_id)
    return if old_image_id.to_s.empty?

    logger.warn "[SearxngUpdaterJob] Rolling back #{container_service} to image #{old_image_id}"

    # Зупиняємо розламаний контейнер і повертаємо Compose на початковий стан
    system("docker", "stop", container_name)
    system("docker", "rm", container_name)

    # Використовуємо Compose для перестворення, але гарантуємо старий образ
    system(
      "docker", "run", "-d",
      "--name", container_name,
      "--network", "#{PROJECT_NAME}_finder_network",
      "-v", "#{WORKING_DIR}/searxng/#{container_service}/settings.yml:/etc/searxng/settings.yml:ro",
      "-v", "#{WORKING_DIR}/searxng/limiter.toml:/etc/searxng/limiter.toml:ro",
      old_image_id
    )

    wait_for_healthy_status(container_name)
  rescue StandardError => e
    logger.error "[SearxngUpdaterJob] Rollback failed for #{container_service}: #{e.message}"
  end

  def current_image_id(container_name)
    capture_cmd("docker", "inspect", "--format", "{{.Image}}", container_name).strip
  end

  def capture_cmd(*args)
    stdout, _status = Open3.capture2e(*args)
    stdout
  rescue StandardError => e
    logger.error "Command execution error #{args.join(' ')}: #{e.message}"
    ""
  end
end
