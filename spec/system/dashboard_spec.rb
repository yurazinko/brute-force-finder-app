# frozen_string_literal: true

require "rails_helper"
require_relative "../support/capybara_cuprite"
require_relative "../support/system_test_helpers"

RSpec.describe "Statistics Dashboard", type: :system do
  let!(:user) { create_system_user }

  before { sign_in_through_ui(user) }

  it "opens the dashboard from the main navigation and shows empty states" do
    click_link "Statistics"

    expect(page).to have_css("h1", text: /Statistics|Dashboard/i)
    expect(page).to have_content("No relevant results found for the selected period.")
    expect(page).to have_content("No low-yield targets found for the selected period.")
  end

  it "keeps dashboard navigation available after changing the reporting period" do
    visit dashboard_path
    expect(page).to have_content(/Most Productive Domains/i)

    select "Last 30 days", from: "period"

    expect(page).to have_current_path(dashboard_path(period: "30"))
    expect(page).to have_content(/Most Productive Domains/i)
    expect(page).to have_link("Campaigns")
  end
end
