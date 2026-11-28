# frozen_string_literal: true

require "rails_helper"
require_relative "../support/capybara_cuprite"
require_relative "../support/system_test_helpers"

RSpec.describe "Authentication", type: :system do
  it "allows a user to sign in and reach the authenticated navigation" do
    user = create_system_user

    visit root_path
    click_link "Log in"
    fill_login_username(user.username)
    fill_login_password(SystemTestHelpers::TEST_PASSWORD)
    click_button "Log in"

    expect(page).to have_link("Quick Search")
    expect(page).to have_link("Campaigns")
    expect(page).to have_link("Results")
    expect(page).to have_link("Targets")
    expect(page).to have_link("Statistics")
    expect(page).to have_link("Sync")
  end

  it "keeps the user on the login form when the password is incorrect" do
    user = create_system_user

    visit new_user_session_path
    fill_login_username(user.username)
    fill_login_password("incorrect-password")
    click_button "Log in"

    expect(page).to have_css("input[name='user[username]']", visible: true)
    expect(page.find("input[name='user[username]']").value).to eq(user.username)
    expect(page).to have_content(/invalid/i)
    expect(page).not_to have_link("Campaigns")
  end

  it "logs out through the Turbo DELETE link" do
    user = create_system_user
    sign_in_through_ui(user)

    click_link "Log out"

    expect(page).to have_field("query")
    expect(page).to have_link("Log in")
    expect(page).not_to have_link("Campaigns")
  end

  it "redirects a guest to login when opening a protected page" do
    visit dashboard_path

    expect(page).to have_css("input[name='user[username]']", visible: true)
    expect(page).to have_css("input[name='user[password]']", visible: true)
  end
end
