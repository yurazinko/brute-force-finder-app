# frozen_string_literal: true

require "rails_helper"
require_relative "../support/capybara_cuprite"
require_relative "../support/system_test_helpers"

RSpec.describe "Results", type: :system do
  let!(:user) { create_system_user }
  let!(:search) do
    search, = create_system_campaign(user: user, title: "Results Workflow Campaign")
    search
  end
  let!(:target) { search.targets.first }

  before { sign_in_through_ui(user) }

  it "moves a result to Starred with one click and removes it from Inbox" do
    result = create_system_result(search: search, target: target)
    visit search_path(search)

    within("#result_#{result.id}") do
      click_button "Move to Starred"
    end

    expect(result.reload.status).to eq("interesting")
    expect(page).to have_no_css("#result_#{result.id}")

    visit search_path(search, status: "interesting")
    expect(page).to have_css("#result_#{result.id}")
  end

  it "moves a result to Trash and restores it to Inbox" do
    result = create_system_result(search: search, target: target)
    visit search_path(search)

    within("#result_#{result.id}") do
      click_button "Move to Trash"
    end

    expect(result.reload.status).to eq("garbage")
    expect(page).to have_no_css("#result_#{result.id}")

    visit search_path(search, status: "garbage")
    within("#result_#{result.id}") do
      click_button "Move to Inbox"
    end

    expect(result.reload.status).to eq("unread")
  end

  it "marks a campaign result as Reviewed when its title receives a contextmenu event" do
    result = create_system_result(search: search, target: target, title: "Context-clicked campaign result")
    visit search_path(search)

    expect(page).to have_css("#result_#{result.id}:not(.opacity-50)")
    expect(find("#result_#{result.id}")["data-controller"]).to include("read-status")
    expect(page).to have_css("#result_#{result.id}[data-read-status-ready='true']")
    expect(find("#result_#{result.id} a[data-read-url]")["data-read-url"]).to eq(
      mark_as_read_result_path(result)
    )
    trigger_context_menu("#result_#{result.id} a[data-read-url]")

    expect(page).to have_css(
      "#result_#{result.id}.opacity-50[data-read-status-current-status-value='watched'][data-read-status-saved='true']"
    )
    expect(result.reload.status).to eq("watched")
    expect(result.reload.acknowledged).to be(true)
  end

  it "navigates between Inbox and Reviewed tabs by clicking the tab controls" do
    reviewed = create_system_result(
      search: search,
      target: target,
      title: "Reviewed through tabs",
      status: "watched",
      acknowledged: true
    )

    visit search_path(search)
    expect(page).to have_no_css("#result_#{reviewed.id}")

    within("#search_tabs_navigation") do
      click_link "Reviewed"
    end

    expect(page).to have_current_path(search_path(search, status: "watched"))
    expect(page).to have_css("#result_#{reviewed.id}")

    within("#search_tabs_navigation") do
      click_link "Inbox"
    end
    expect(page).to have_current_path(search_path(search))
    expect(page).to have_no_css("#result_#{reviewed.id}")
  end

  it "changes the result time window by clicking Past Week" do
    recent = create_system_result(search: search, target: target, title: "Recent result")
    old = create_system_result(search: search, target: target, title: "Old result")
    old.update_columns(created_at: 3.months.ago, updated_at: 3.months.ago)

    visit search_path(search)
    expect(page).to have_css("#result_#{recent.id}")
    expect(page).to have_css("#result_#{old.id}")

    click_link "Past Week"

    expect(page).to have_current_path(search_path(search, d: "week"))
    expect(page).to have_css("#result_#{recent.id}")
    expect(page).to have_no_css("#result_#{old.id}")
  end

  it "sorts matching result cards by newest first after clicking Newest" do
    older = create_system_result(search: search, target: target, title: "Older result")
    newer = create_system_result(search: search, target: target, title: "Newer result")
    older.update_columns(created_at: 2.days.ago, updated_at: 2.days.ago)
    newer.update_columns(created_at: 1.hour.ago, updated_at: 1.hour.ago)

    visit search_path(search)
    click_link "Newest"

    expect(page).to have_current_path(search_path(search, sort: "created_desc"))
    card_ids = page.all("#results_pool_list > div").pluck(:id)
    expect(card_ids.index("result_#{newer.id}")).to be < card_ids.index("result_#{older.id}")
  end

  it "filters results by visible text using the search field" do
    ruby_result = create_system_result(
      search: search,
      target: target,
      title: "Ruby Rails Engineer",
      content: "Ruby backend role"
    )
    create_system_result(
      search: search,
      target: target,
      title: "Elixir Phoenix Engineer",
      content: "Elixir backend role"
    )

    visit search_path(search)
    fill_in "Filter matches...", with: "Elixir"
    click_button "Apply"

    expect(page).to have_content("Elixir Phoenix Engineer")
    expect(page).not_to have_content("Ruby Rails Engineer")
    expect(ruby_result.reload.status).to eq("unread")
  end

  it "opens the target-pattern configuration modal from a result card" do
    result = create_system_result(search: search, target: target)
    visit search_path(search)

    within("#result_#{result.id}") do
      click_link "Configure"
    end

    expect(page).to have_css("#modal h3", text: "Configure Link Pattern and Target")
    expect(page).to have_css("[data-controller='path-builder']")

    find("#modal a[aria-label='Close target configuration']").click
    expect(page).to have_no_css("#modal h3", text: "Configure Link Pattern and Target")
  end

  it "filters the global Results page by campaign selection" do
    result = create_system_result(search: search, target: target, title: "Campaign Filter Result")
    visit results_path

    check(search.title)

    expect(page).to have_css("#result_#{result.id}")
  end

  it "removes results from other campaigns when the global campaign filter is narrowed" do
    own_result = create_system_result(search: search, target: target, title: "Selected Campaign Result")
    other_search, = create_system_campaign(user: user, title: "Other Results Campaign")
    other_target = other_search.targets.first
    other_result = create_system_result(
      search: other_search,
      target: other_target,
      title: "Unselected Campaign Result"
    )

    visit results_path
    check(search.title)

    expect(page).to have_css("#result_#{own_result.id}")
    expect(page).to have_no_css("#result_#{other_result.id}")
  end

  it "shows acknowledged results only after the user enables Show Acknowledged" do
    result = create_system_result(
      search: search,
      target: target,
      title: "Previously Reviewed Result",
      acknowledged: true
    )
    visit results_path

    expect(page).to have_no_css("#result_#{result.id}")
    check "Show Acknowledged"

    expect(page).to have_css("#result_#{result.id}")
  end

  it "applies a bulk Starred action to all matching results" do
    first = create_system_result(search: search, target: target, title: "Bulk Result One")
    second = create_system_result(search: search, target: target, title: "Bulk Result Two")
    visit search_path(search)

    within("#bulk_actions_top") do
      select "all results", from: "bulk_scope_top"
      accept_confirm do
        click_button "Starred"
      end
    end

    expect(first.reload.status).to eq("interesting")
    expect(second.reload.status).to eq("interesting")
  end
end
