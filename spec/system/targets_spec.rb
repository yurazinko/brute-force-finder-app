# frozen_string_literal: true

require "rails_helper"
require_relative "../support/capybara_cuprite"
require_relative "../support/system_test_helpers"

RSpec.describe "Targets", type: :system do
  let!(:user) { create_system_user }
  let!(:category) do
    Category.create!(user: user, name: "Target UI Category")
  end
  let!(:target) do
    Target.create!(
      category: category,
      name: "Example Board",
      domain: "example-board.test",
      is_active: true
    )
  end

  before { sign_in_through_ui(user) }

  it "opens the unified React target editor from a category" do
    visit category_path(category)
    click_link "Add New Target"

    expect(page).to have_css("[data-controller='path-builder'][data-path-builder-mode-value='target']")
    expect(page).to have_css("[data-path-builder-target-category-id-value='#{category.id}']")
  end

  it "opens the editor for an existing target" do
    visit category_path(category)
    within("#target_#{target.id}") do
      click_link "Edit"
    end

    expect(page).to have_css("[data-controller='path-builder'][data-path-builder-mode-value='target']")
    expect(page).to have_css("[data-path-builder-target-id-value='#{target.id}']")
    expect(page).to have_css("[data-path-builder-target-name-value='Example Board']")
  end

  it "toggles a target from Active to Disabled" do
    visit category_path(category)
    within("#target_#{target.id}") do
      click_button "Active"
    end

    expect(target.reload.is_active).to be(false)
    visit category_path(category)
    within("#target_#{target.id}") do
      expect(page).to have_button("Disabled")
    end
  end

  it "deletes a target from the category list" do
    visit category_path(category)
    within("#target_#{target.id}") do
      accept_confirm { click_button "Delete" }
    end

    expect(Target.exists?(target.id)).to be(false)
    expect(page).to have_content("No target sites have been added to this category yet.")
  end
end
