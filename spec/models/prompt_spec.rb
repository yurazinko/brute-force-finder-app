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
    let(:category) { Category.create!(name: "Tech Platforms") }
    let(:target) { Target.create!(category: category, name: "Lever", domain: "lever-#{SecureRandom.hex(4)}.co") }
    let(:search) { Search.create!(title: "Ruby Job", query_conditions: "ruby", status: "pending") }

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

    it "is invalid without full_query_text" do
      prompt = described_class.new(full_query_text: nil)
      prompt.valid?
      expect(prompt.errors[:full_query_text]).to include("can't be blank")
    end

    it "is invalid with an incorrect status" do
      prompt = described_class.new(
        search: search,
        target: target,
        full_query_text: "site:lever.co ruby",
        status: "archived"
      )

      prompt.valid?
      expect(prompt.errors[:status]).to include("is not included in the list")
    end
  end
end
