# frozen_string_literal: true

require "rails_helper"

RSpec.describe Category, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      category = described_class.new(name: "ATS Platforms")
      expect(category).to be_valid
    end

    it "is invalid without a name" do
      category = described_class.new(name: nil)
      category.valid?
      expect(category.errors[:name]).to include("can't be blank")
    end

    it "is invalid with a duplicate name" do
      described_class.create!(name: "Real Estate")

      duplicate_category = described_class.new(name: "Real Estate")
      duplicate_category.valid?

      expect(duplicate_category.errors[:name]).to include("has already been taken")
    end
  end

  describe "associations" do
    it "has many targets with dependent destroy" do
      association = described_class.reflect_on_association(:targets)

      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end

    it "deletes associated targets when category is destroyed" do
      category = described_class.create!(name: "Boards")

      target = Target.create!(
        category: category,
        name: "Unique Board",
        domain: "unique-#{SecureRandom.hex(4)}.com"
      )

      expect { category.destroy }.to change(Target, :count).by(-1)
      expect(Target.exists?(id: target.id)).to be_falsy
    end
  end
end
