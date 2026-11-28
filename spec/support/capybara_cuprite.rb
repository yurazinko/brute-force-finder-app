# frozen_string_literal: true

require "capybara/cuprite"

Capybara.default_max_wait_time = 7
Capybara.server = :puma
Capybara.server_host = ENV.fetch("CAPYBARA_SERVER_HOST", "127.0.0.1")
Capybara.javascript_driver = :cuprite

RSpec.configure do |config|
  config.before(:suite) do
    # Capybara probes its Puma server over localhost before opening the browser.
    # Keep external HTTP blocked while allowing that internal health check.
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  config.before(:each, type: :system) do
    browser_candidates = [
      ENV["BROWSER_PATH"],
      ENV["CHROME_BIN"],
      "/opt/chrome-for-testing/chrome",
      "/usr/bin/chromium",
      "/usr/bin/chromium-browser",
      "/usr/bin/google-chrome",
      "/usr/bin/google-chrome-stable"
    ]
    browser_candidates.compact!
    browser_candidates.uniq!

    browser_path = browser_candidates.find do |candidate|
      File.file?(candidate) && File.executable?(candidate)
    end

    unless browser_path
      raise <<~ERROR
        Cuprite cannot find Chrome/Chromium.
        Checked: #{browser_candidates.join(', ')}
        Install Chrome for Testing in the environment running RSpec, or set
        BROWSER_PATH to the absolute path of the browser executable.
      ERROR
    end

    browser_options = {
      "disable-dev-shm-usage" => nil,
      "disable-gpu" => nil,
      "disable-extensions" => nil,
      "no-first-run" => nil,
      "no-default-browser-check" => nil,
      "disable-background-networking" => nil
    }
    # The development Compose container currently runs as root. Do not disable
    # Chrome's sandbox for normal non-root local/CI runs.
    browser_options["no-sandbox"] = nil if Process.uid.zero?

    cuprite_options = {
      browser_path: browser_path,
      browser_options: browser_options,
      headless: true,
      js_errors: true,
      process_timeout: Integer(
        ENV.fetch("CUPRITE_PROCESS_TIMEOUT", ENV.fetch("FERRUM_PROCESS_TIMEOUT", "60"))
      ),
      timeout: 20
    }

    # IMPORTANT: RSpec Rails' driven_by(:cuprite) registers a Capybara driver
    # itself. Pass options here; a separate Capybara.register_driver(:cuprite)
    # would be overwritten by this registration on every system example.
    driven_by(
      :cuprite,
      screen_size: [1440, 1000],
      options: cuprite_options
    )
  end

  # Ferrum stores Chrome's stdout/stderr on ProcessTimeoutError#output. Print
  # it explicitly so a real browser startup failure is diagnosable from RSpec.
  config.around(:each, type: :system) do |example|
    example.run
  rescue Ferrum::ProcessTimeoutError => error
    warn "\n[Cuprite] Browser startup timed out."
    warn "[Cuprite] BROWSER_PATH=#{ENV['BROWSER_PATH'].inspect}"
    warn "[Cuprite] CUPRITE_PROCESS_TIMEOUT=#{ENV['CUPRITE_PROCESS_TIMEOUT'].inspect}"
    warn "[Cuprite] Ferrum process output:\n#{error.output}"
    raise
  end
end
