# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"
require_relative "../support/capybara_cuprite"
require_relative "../support/system_test_helpers"

RSpec.describe "Quick Search", type: :system do
  before do
    Sidekiq::Testing.fake!
    QuickSearches::ActivationJob.jobs.clear
    allow(QuickSearches::ActivationJob).to receive(:perform_async).and_return("quick-search-job")
  end

  it "lets a guest submit a query without creating a persistent campaign" do
    token = nil
    visit root_path

    expect(page).to have_field("query")
    expect(page).to have_button("🔍 Search")

    expect do
      fill_in "query", with: "Ruby on Rails remote jobs"
      click_button "🔍 Search"
      expect(page).to have_content("Preparing your search…")
      token = Rack::Utils.parse_nested_query(URI(page.current_url).query)["quick_search"]
    end.not_to change(Search, :count)

    expect(token).to be_present
    expect(QuickSearches::ActivationJob).to have_received(:perform_async).with(token, nil)
    expect(page).to have_button("🧹 Clear results")
  ensure
    clear_seeded_quick_search(token)
  end

  it "does not submit an empty query because the browser form marks it required" do
    visit root_path

    fill_in "query", with: ""
    click_button "🔍 Search"

    expect(page).to have_current_path(root_path)
    expect(QuickSearches::ActivationJob).not_to have_received(:perform_async)
    expect(page).to have_field("query", with: "")
  end

  it "clears the current temporary search from the visible page" do
    visit root_path
    fill_in "query", with: "Ruby developer"
    click_button "🔍 Search"
    expect(page).to have_button("🧹 Clear results")

    accept_confirm do
      click_button("🧹 Clear results")
    end

    expect(page).to have_field("query", with: "")
    expect(page).not_to have_button("🧹 Clear results")
    expect(page).not_to have_content("Preparing your search…")
  end

  it "shows a completed quick search and opens the prefilled campaign form for an authenticated user" do
    user = create_system_user
    sign_in_through_ui(user)
    token, = seed_completed_quick_search(user_id: user.id)

    begin
      visit root_path(quick_search: token)

      expect(page).to have_content("Ruby Quick Search Result")
      expect(page).to have_link("Save as campaign")
      click_link "Save as campaign"

      expect(page).to have_css("h1", text: "Create New Search Campaign")
      expect(page).to have_field("Campaign Title", with: "Search for Ruby on Rails")
      expect(page).to have_css(
        "[data-react-portal-initial-value-value='\"Ruby\" \"on\" \"Rails\"']"
      )
      expect(page).to have_field("quick_search_token", with: token, type: :hidden)
    ensure
      clear_seeded_quick_search(token)
    end
  end

  it "marks a quick-search result as reviewed when its title receives a contextmenu event" do
    token, result_hash = seed_completed_quick_search(user_id: nil)

    begin
      visit root_path(quick_search: token)
      card = find("#quick_result_#{result_hash}")
      expect(card[:class]).not_to include("opacity-50")
      expect(card["data-controller"]).to include("read-status")
      expect(page).to have_css("#quick_result_#{result_hash}[data-read-status-ready='true']")
      expect(find("#quick_result_#{result_hash} a[data-read-url]")["data-read-url"]).to be_present

      trigger_context_menu("#quick_result_#{result_hash} a[data-read-url]")

      expect(page).to have_css(
        "#quick_result_#{result_hash}.opacity-50[data-read-status-current-status-value='watched'][data-read-status-saved='true']"
      )
      expect(QuickSearch::Store.result(token, url_hash: result_hash).fetch("status")).to eq("watched")
      expect(QuickSearch::Store.result(token, url_hash: result_hash).fetch("acknowledged")).to be(true)
    ensure
      clear_seeded_quick_search(token)
    end
  end

  it "imports completed quick-search results with their reviewed state when saving a campaign" do
    user = create_system_user
    sign_in_through_ui(user)
    token, result_hash = seed_completed_quick_search(
      user_id: user.id,
      result_attributes: {
        status: "watched",
        acknowledged: true,
        relevance_score: 95,
        matched_keywords: %w[Ruby Rails]
      }
    )

    begin
      visit root_path(quick_search: token)
      click_link "Save as campaign"
      expect(page).to have_css("h1", text: "Create New Search Campaign")

      expect do
        click_button "Save Criteria"
      end.to change(Search, :count).by(1)

      campaign = user.searches.order(:id).last
      imported = campaign.results.find_by!(url_hash: result_hash)

      expect(imported.status).to eq("watched")
      expect(imported.acknowledged).to be(true)
      expect(imported.relevance_score).to eq(95)
      expect(imported.matched_keywords).to eq(%w[Ruby Rails])
      expect(page).to have_css("h1", text: campaign.title)
    ensure
      clear_seeded_quick_search(token)
    end
  end

  it "requires guest authentication before continuing to Save as campaign" do
    token, = seed_completed_quick_search(user_id: nil)
    user = create_system_user

    begin
      visit root_path(quick_search: token)
      click_link "Save as campaign"

      expect(page).to have_css("input[name='user[username]']", visible: true)
      fill_login_username(user.username)
      fill_login_password(SystemTestHelpers::TEST_PASSWORD)
      click_button "Log in"

      expect(page).to have_css("h1", text: "Create New Search Campaign")
      expect(page).to have_field("quick_search_token", with: token, type: :hidden)
    ensure
      clear_seeded_quick_search(token)
    end
  end
end
