# frozen_string_literal: true

require "rails_helper"

RSpec.describe Target, type: :model do
  let(:category) { Category.create!(name: "Jobs") }

  describe "validations" do
    it "is valid with valid attributes" do
      target = described_class.new(
        category: category,
        name: "Lever",
        domain: "lever.co",
        is_active: true
      )
      expect(target).to be_valid
    end

    it "is invalid without a name" do
      target = described_class.new(name: nil, domain: "lever.co", category: category)
      target.valid?
      expect(target.errors[:name]).to include("can't be blank")
    end

    it "is invalid with a duplicate domain" do
      unique_domain = "lever-#{SecureRandom.hex(4)}.co"
      described_class.create!(category: category, name: "Lever 1", domain: unique_domain)

      duplicate_target = described_class.new(category: category, name: "Lever 2", domain: unique_domain)
      duplicate_target.valid?

      expect(duplicate_target.errors[:domain]).to include("has already been taken")
    end
  end

  describe "associations" do
    it "belongs to category" do
      association = described_class.reflect_on_association(:category)
      expect(association.macro).to eq(:belongs_to)
    end

    it "has many prompts with dependent destroy" do
      association = described_class.reflect_on_association(:prompts)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end
  end

  describe "scopes" do
    describe ".active" do
      let!(:active_target) { described_class.create!(category: category, name: "Active", domain: "active-#{SecureRandom.hex(4)}.com", is_active: true) }
      let!(:inactive_target) { described_class.create!(category: category, name: "Inactive", domain: "inactive-#{SecureRandom.hex(4)}.com", is_active: false) }

      it "returns only targets where is_active is true" do
        expect(described_class.active).to include(active_target)
        expect(described_class.active).not_to include(inactive_target)
      end
    end
  end
end
