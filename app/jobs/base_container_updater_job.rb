# frozen_string_literal: true

require "open3"
require "json"
require "uri"
require "socket"
require "net/http"

class BaseContainerUpdaterJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 0

  PROJECT_NAME = ENV.fetch("COMPOSE_PROJECT_NAME", "brute-force-finder-app")

  def perform
    pull_latest_image

    containers_to_update.each do |container_info|
      process_container_update(container_info)
    end
  end

  private

  def image_name
    raise NotImplementedError, "#{self.class} must implement #image_name"
  end

  def containers_to_update
    raise NotImplementedError, "#{self.class} must implement #containers_to_update"
  end

  def run_smoke_test(_container_info); end

  def pull_latest_image
    logger.info "[#{self.class.name}] Pulling latest image: #{image_name}"
    success = system("docker", "pull", image_name)

    raise "Failed to pull image #{image_name}" unless success
  end

  def process_container_update(info) # rubocop:disable Metrics/AbcSize
    service_name = info[:service]
    container_name = info[:container_name]

    logger.info "[#{self.class.name}] Updating #{service_name} via Docker Compose (path: #{host_project_path})..."

    raise "Failed to execute docker compose recreate for #{service_name}" unless recreate_container(service_name)

    begin
      wait_for_healthy_status(container_name)
      run_smoke_test(info)
      logger.info "[#{self.class.name}] Successfully updated and verified #{service_name}"
    rescue StandardError => e
      logger.error "[#{self.class.name}] #{service_name} update failed: #{e.message}"
      raise e
    end
  end

  def recreate_container(service_name)
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
      service_name
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

      return if %w[healthy running].include?(status)
    end

    logs = capture_cmd("docker", "logs", "--tail", "20", container_name)
    last_status = capture_cmd("docker", "inspect", "--format", "{{.State.Status}}", container_name).strip

    raise "Container #{container_name} failed check (status: '#{last_status}'). Logs:\n#{logs}"
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
    logger.error "[#{self.class.name}] Command execution error #{args.join(' ')}: #{e.message}"
    ""
  end
end
