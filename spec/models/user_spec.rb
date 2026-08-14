# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it "has many searches with dependent destroy" do
      association = described_class.reflect_on_association(:searches)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end

    it "has many categories with dependent destroy" do
      association = described_class.reflect_on_association(:categories)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end
  end

  describe "validations" do
    subject(:user) { build(:user) }

    it "is valid with valid attributes" do
      expect(user).to be_valid
    end

    it "is invalid without an email" do
      user.email = nil
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("can't be blank")
    end

    it "is invalid with a duplicate email" do
      create(:user, email: "test@example.com")
      duplicate_user = build(:user, email: "TEST@example.com")

      expect(duplicate_user).not_to be_valid
      expect(duplicate_user.errors[:email]).to include("has already been taken")
    end

    it "is invalid without a password" do
      user.password = nil
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("can't be blank")
    end

    it "is invalid with a short password" do
      user.password = "12345"
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("is too short (minimum is 6 characters)")
    end
  end

  describe "dependent destruction" do
    let!(:user) { create(:user) }

    it "destroys associated searches when user is deleted" do
      create_list(:search, 2, user: user)

      expect { user.destroy }.to change(Search, :count).by(-2)
    end

    it "destroys associated categories when user is deleted" do
      create_list(:category, 2, user: user)

      expect { user.destroy }.to change(Category, :count).by(-2)
    end
  end
end
