# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"
require_relative "../support/capybara_cuprite"
require_relative "../support/system_test_helpers"

RSpec.describe "Search Campaigns", type: :system do
  let!(:user) { create_system_user }

  before { sign_in_through_ui(user) }

  it "lists only campaigns owned by the signed-in user" do
    own_search, = create_system_campaign(user: user, title: "My Ruby Campaign")
    other_user = create_system_user
    create_system_campaign(user: other_user, title: "Another User Campaign")

    visit searches_path

    expect(page).to have_link("My Ruby Campaign")
    expect(page).not_to have_content("Another User Campaign")
    expect(Search.exists?(own_search.id)).to be(true)
  end

  it "opens a campaign and displays its query and results area" do
    create_system_campaign(user: user, title: "Ruby Backend Campaign")

    visit searches_path
    click_link "Ruby Backend Campaign"

    expect(page).to have_css("h1", text: "Ruby Backend Campaign")
    expect(page).to have_content(/Target Query Filter/i)
    expect(page).to have_content("Discovered Results")
    expect(page).to have_button("Pause")
  end

  it "pauses and resumes campaign scans through the action buttons" do
    search, = create_system_campaign(user: user, title: "Pause Resume Campaign")
    visit search_path(search)

    click_button "Pause"
    expect(page).to have_button("Resume")
    expect(search.reload).to be_paused

    click_button "Resume"
    expect(page).to have_button("Pause")
    expect(search.reload).not_to be_paused
  end

  it "marks a processing campaign complete" do
    search, = create_system_campaign(user: user, title: "Complete Campaign", status: "processing")
    visit search_path(search)

    expect(page).to have_button("Complete", disabled: false)
    accept_confirm do
      click_button "Complete"
    end

    expect(search.reload.status).to eq("completed")
    expect(page).to have_content("Campaign completed.")
  end

  it "opens a cloned campaign form with the source settings prefilled" do
    search, = create_system_campaign(user: user, title: "Clone Source")
    visit search_path(search)

    find("a[aria-label='Clone campaign settings']").click

    expect(page).to have_css("h1", text: "Create New Search Campaign")
    expect(page).to have_field("Campaign Title", with: "Clone Source (Copy)")
    # The Dork Builder represents whitespace-separated terms as separate
    # condition groups and serializes them into its normalized raw query.
    # The React builder submits its normalized query through a hidden input.
    # Capybara's generic field selector excludes hidden inputs unless the type is explicit.
    query_field = find(
      "input[type='hidden'][name='search[query_conditions]']",
      visible: :all
    )
    expect(query_field.value).to eq('("ruby") ("developer")')
  end

  it "updates the campaign title through the edit form" do
    search, = create_system_campaign(user: user, title: "Campaign Before Edit")
    visit search_path(search)
    find("a[aria-label='Edit campaign settings']").click

    expect(page).to have_css("h1", text: "Configure Search Campaign")
    fill_in "Campaign Title", with: "Campaign After Edit"
    click_button "Update Campaign Criteria"

    expect(page).to have_css("h1", text: "Campaign After Edit")
    expect(search.reload.title).to eq("Campaign After Edit")
  end

  it "selects and clears all target checkboxes using the Stimulus controls" do
    _search, _category, target = create_system_campaign(user: user)
    visit new_search_path

    expect(page).to have_css("input.target-item-checkbox:not(:checked)")
    click_button "Select All"
    expect(page).to have_css("input.target-item-checkbox:checked", count: 1)

    click_button "Clear All"
    expect(page).to have_css("input.target-item-checkbox:not(:checked)", count: 1)
    expect(target).to be_persisted
  end

  it "selects and clears discovery sources through the campaign-page Stimulus controller" do
    search, _category, target = create_system_campaign(user: user)
    visit search_path(search)

    within("#targets_selector_zone") do
      expect(page).to have_css("input[name='target_ids[]']:checked", count: 1)
    end

    # The global Select All / Clear All controls intentionally sit above,
    # outside the scrolling targets zone.
    click_button "Clear All"
    within("#targets_selector_zone") do
      expect(page).to have_css("input[name='target_ids[]']:not(:checked)", count: 1)
    end

    click_button "Select All"
    within("#targets_selector_zone") do
      expect(page).to have_css("input[name='target_ids[]']:checked", count: 1)
    end
    expect(target).to be_persisted
  end

  it "persists the Show globally processed results setting from the edit form" do
    search, = create_system_campaign(user: user, title: "Acknowledged Setting")
    visit edit_search_path(search)

    check "Show globally processed results"
    click_button "Update Campaign Criteria"

    expect(search.reload.show_acknowledged).to be(true)
    expect(page).to have_css("h1", text: "Acknowledged Setting")
  end

  it "starts discovery only for the target selected on the campaign page" do
    search, category, selected_target = create_system_campaign(user: user)
    unselected_target = Target.create!(
      category: category,
      name: "Unselected Board #{SecureRandom.hex(3)}",
      domain: "unselected-#{SecureRandom.hex(3)}.example.test",
      is_active: true
    )
    visit search_path(search)

    within("#targets_selector_zone") do
      uncheck selected_target.name
      check unselected_target.name
    end

    click_button("🚀 Run Discovery Now")

    expect(page).to have_content("Scraping pipeline successfully initialized!")
    expect(search.reload.status).to eq("processing")
    expect(search.target_ids).to contain_exactly(unselected_target.id)
    expect(search.prompts.pluck(:target_id)).to contain_exactly(unselected_target.id)
  end

  it "deletes a campaign after the confirmation dialog is accepted" do
    search, = create_system_campaign(user: user, title: "Campaign To Delete")
    visit search_path(search)

    accept_confirm do
      find("button[aria-label='Delete campaign']").click
    end

    expect(Search.exists?(search.id)).to be(false)
    expect(page).to have_current_path(searches_path)
    expect(page).not_to have_content("Campaign To Delete")
  end
end
