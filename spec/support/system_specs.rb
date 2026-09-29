# frozen_string_literal: true

require "capybara/cuprite"

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :cuprite, using: :chrome, options: {
      js_errors: true,
      window_size: [1280, 800],
      browser_options: { "no-sandbox" => nil }
    }
  end
end
