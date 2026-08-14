# frozen_string_literal: true

require "rails_helper"

RSpec.describe Prompt, type: :model do
  describe "associations" do
    it "belongs to search" do
      association = described_class.reflect_on_association(:search)
      expect(association.macro).to eq(:belongs_to)
    end

    it "belongs to target" do
      association = described_class.reflect_on_association(:target)
      expect(association.macro).to eq(:belongs_to)
    end
  end

  describe "validations" do
    let(:user) { create(:user) }
    let(:category) { Category.create!(name: "Tech Platforms") }
    let(:target) { Target.create!(category: category, name: "Lever", domain: "lever.co") }
    let(:search) { Search.create!(user: user, title: "Ruby Job", query_conditions: "ruby", status: "pending") }

    it "is valid with valid attributes and a correct status" do
      %w[pending active failed success].each do |valid_status|
        prompt = described_class.new(
          search: search,
          target: target,
          full_query_text: "site:lever.co ruby",
          status: valid_status
        )
        expect(prompt).to be_valid
      end
    end

    it "is invalid with an incorrect status" do
      prompt = described_class.new(
        search: search,
        target: target,
        full_query_text: "site:lever.co ruby",
        status: "archived"
      )

      expect(prompt).not_to be_valid
      expect(prompt.errors[:status]).to include("is not included in the list")
    end

    it "is invalid without full_query_text if search or target are missing" do
      prompt = described_class.new(
        search: nil,
        target: nil,
        full_query_text: nil,
        status: "pending"
      )

      expect(prompt).not_to be_valid
      expect(prompt.errors[:full_query_text]).to include("can't be blank")
    end
  end

  describe "callbacks" do
    describe "before_validation :generate_full_query_text" do
      let(:user) { create(:user) }
      let(:category) { Category.create!(name: "Tech Platforms") }
      let(:target) { Target.create!(category: category, name: "Lever", domain: "lever.co") }
      let(:search) { Search.create!(user: user, title: "Ruby Job", query_conditions: "ruby", status: "pending") }

      context "when full_query_text is blank" do
        it "automatically generates the correct query text before running validations" do
          prompt = described_class.new(
            search: search,
            target: target,
            full_query_text: nil,
            status: "pending"
          )

          expect(prompt).to be_valid
          expect(prompt.full_query_text).to eq("site:lever.co ruby")
        end
      end

      context "when full_query_text is already explicitly provided" do
        it "does not overwrite the existing text" do
          custom_query = "site:lever.co rails custom_filter"
          prompt = described_class.new(
            search: search,
            target: target,
            full_query_text: custom_query,
            status: "pending"
          )

          expect(prompt).to be_valid
          expect(prompt.full_query_text).to eq(custom_query)
        end
      end
    end
  end
end
