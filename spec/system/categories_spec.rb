# frozen_string_literal: true

require "rails_helper"
require_relative "../support/capybara_cuprite"
require_relative "../support/system_test_helpers"

RSpec.describe "Target Categories", type: :system do
  let!(:user) { create_system_user }

  before { sign_in_through_ui(user) }

  it "does not show categories belonging to another account" do
    Category.create!(user: user, name: "My Private Category")
    other_user = create_system_user
    Category.create!(user: other_user, name: "Another Account Category")

    visit categories_path

    expect(page).to have_content("My Private Category")
    expect(page).not_to have_content("Another Account Category")
  end

  it "does not open another user's category by guessing its URL" do
    other_user = create_system_user
    foreign_category = Category.create!(user: other_user, name: "Private Foreign Category")

    visit category_path(foreign_category)

    expect(page).not_to have_content("Private Foreign Category")
    expect(page).not_to have_css("h1", text: /Manage Category:/)
  end

  it "opens the target management page from a category card" do
    Category.create!(user: user, name: "Manage Me")

    visit categories_path
    click_link "Manage Sites"

    expect(page).to have_css("h1", text: "Manage Category: Manage Me")
    expect(page).to have_content("No target sites have been added to this category yet.")
  end

  it "creates a category through the form" do
    visit categories_path
    click_link "Create New Category"

    fill_in "Category Name", with: "ATS Platforms"
    click_button "Save Category"

    expect(page).to have_content("ATS Platforms")
    expect(Category.find_by!(user: user, name: "ATS Platforms")).to be_present
  end

  it "shows validation feedback when a category name is blank" do
    visit new_category_path
    click_button "Save Category"

    expect(page).to have_content("Name can't be blank")
    expect(page).to have_css("form")
  end

  it "renames an existing category from the categories list" do
    category = Category.create!(user: user, name: "Job Boards")

    visit categories_path
    within("body") { click_link "Rename" }
    fill_in "Category Name", with: "Global Job Boards"
    click_button "Update Category"

    expect(page).to have_content("Global Job Boards")
    expect(category.reload.name).to eq("Global Job Boards")
  end

  it "deletes a category and its linked targets after confirmation" do
    category = Category.create!(user: user, name: "Temporary Sources")
    target = Target.create!(category: category, name: "Temporary Board", domain: "temporary.example.test")

    visit categories_path
    accept_confirm do
      within("body") { click_button "Delete" }
    end

    expect(page).not_to have_content("Temporary Sources")
    expect(Category.exists?(category.id)).to be(false)
    expect(Target.exists?(target.id)).to be(false)
  end
end
