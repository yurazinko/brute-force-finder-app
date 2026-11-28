# frozen_string_literal: true

module SystemTestHelpers
  TEST_PASSWORD = "Browser-test-password-2026!"
end

module SystemTestUserHelpers
  def create_system_user(username: nil, password: SystemTestHelpers::TEST_PASSWORD)
    User.create!(
      username: username || "bf-#{SecureRandom.hex(7)}@example.test",
      password: password,
      password_confirmation: password
    )
  end
end

module SystemTestAuthenticationHelpers
  def fill_login_username(value)
    login_input("input[name='user[username]']", "username").set(value)
  end

  def fill_login_password(value)
    login_input("input[name='user[password]']", "password").set(value)
  end

  def sign_in_through_ui(user, password: SystemTestHelpers::TEST_PASSWORD)
    visit new_user_session_path
    fill_login_username(user.username)
    fill_login_password(password)
    click_button "Log in"
    expect(page).to have_link("Campaigns")
  end

  private

  def login_input(selector, field_name)
    page.find(selector, visible: true)
  rescue Capybara::ElementNotFound => error
    inputs = page.all("input", visible: :all).map { |field| login_input_details(field) }
    raise_login_input_error(selector, field_name, inputs, error)
  end

  def login_input_details(field)
    { name: field["name"], id: field["id"], type: field["type"], disabled: field.disabled? }
  end

  def raise_login_input_error(selector, field_name, inputs, error)
    raise Capybara::ElementNotFound,
          "Could not find the visible Devise #{field_name} input (#{selector}). " \
          "Current URL: #{page.current_url}; title: #{page.title.inspect}; " \
          "inputs on page: #{inputs.inspect}. Original error: #{error.message}"
  end
end

module SystemTestInteractionHelpers
  def trigger_context_menu(selector)
    page.execute_script(context_menu_script(selector))
  end

  private

  def context_menu_script(selector)
    <<~JS
      const link = document.querySelector(#{selector.to_json})
      if (!link) throw new Error("Context-menu target was not found")

      const eventOptions = { bubbles: true, cancelable: true, view: window, button: 2, buttons: 2 }
      link.dispatchEvent(new PointerEvent("pointerdown", {
        ...eventOptions, pointerId: 1, pointerType: "mouse", isPrimary: true
      }))
      link.dispatchEvent(new MouseEvent("mousedown", eventOptions))
      link.dispatchEvent(new MouseEvent("contextmenu", eventOptions))
    JS
  end
end

module SystemTestCampaignHelpers
  def create_system_campaign(user:, title: "Ruby System Campaign", status: "pending")
    suffix = SecureRandom.hex(4)
    category = create_system_category(user, suffix)
    target = create_system_target(category, suffix)
    search = create_system_search(user, target, title, status)
    [search, category, target]
  end

  def create_system_result(search:, target:, **attributes)
    result_attributes = default_system_result_attributes.merge(attributes)
    result_attributes[:content] ||= "Ruby Rails backend developer role"
    Result.create!(result_attributes.merge(
      { search: search, target: target }.merge(system_result_url_attributes(target))
    ))
  end

  private

  def create_system_category(user, suffix)
    Category.create!(user: user, name: "System Category #{suffix}")
  end

  def create_system_target(category, suffix)
    Target.create!(
      category: category,
      name: "Example Board #{suffix}",
      domain: "board-#{suffix}.example.test",
      is_active: true
    )
  end

  def create_system_search(user, target, title, status)
    Search.create!(
      user: user,
      title: title,
      query_conditions: "ruby developer",
      time_frame: "week",
      relevance_mode: "balanced",
      status: status,
      targets: [target]
    )
  end

  def default_system_result_attributes
    { title: "Ruby developer role", status: "unread", acknowledged: false, content: nil }
  end

  def system_result_url_attributes(target)
    url = "https://#{target.domain}/jobs/#{SecureRandom.hex(4)}"
    { url: url, url_hash: Digest::SHA256.hexdigest(url), engine: "System test",
      relevance_score: 100, matched_keywords: %w[ruby developer], verification_status: "verified" }
  end
end

module SystemTestQuickSearchHelpers
  def seed_completed_quick_search(user_id:, query: "Ruby on Rails", result_attributes: {})
    token = SecureRandom.hex(16)
    result_hash = "system-#{SecureRandom.hex(8)}"
    QuickSearch::Store.create!(token: token, user_id: user_id, query: query)
    append_quick_search_result(token, result_hash, result_attributes)
    complete_quick_search(token)
    [token, result_hash]
  end

  def clear_seeded_quick_search(token)
    QuickSearch::Store.clear!(token) if token.present?
  rescue StandardError
    # Redis cleanup must not hide the original system-test failure.
    nil
  end

  private

  def append_quick_search_result(token, result_hash, result_attributes)
    result = quick_search_result_attributes(result_hash).merge(result_attributes.stringify_keys)
    QuickSearch::Store.append_results(token, [result])
  end

  def quick_search_result_attributes(result_hash)
    {
      url: "https://example.test/jobs/#{result_hash}",
      url_hash: result_hash,
      title: "Ruby Quick Search Result",
      content: "Ruby on Rails backend role",
      engine: "SearXNG",
      status: "unread",
      acknowledged: false,
      relevance_score: 100,
      matched_keywords: ["Ruby", "Rails"],
      verification_status: "verified",
      created_at: Time.current.iso8601
    }
  end

  def complete_quick_search(token)
    QuickSearch::Store.update!(
      token,
      {
        status: "completed",
        results_count: 1,
        message: "Search complete — 1 results found.",
        engines_finished: true
      }
    )
  end
end

module SystemTestHelpers
  include SystemTestUserHelpers
  include SystemTestAuthenticationHelpers
  include SystemTestInteractionHelpers
  include SystemTestCampaignHelpers
  include SystemTestQuickSearchHelpers
end

RSpec.configure do |config|
  config.include SystemTestHelpers, type: :system
end
