# frozen_string_literal: true

require "rails_helper"

RSpec.describe Result, type: :model do
  describe "associations" do
    it "belongs to search" do
      association = described_class.reflect_on_association(:search)
      expect(association.macro).to eq(:belongs_to)
    end
  end

  describe "database structural integrity" do
    it "requires an associated search to be valid" do
      result = described_class.new(search: nil)
      expect(result).not_to be_valid
    end

    it "is valid when linked to a search instance" do
      search = Search.new(title: "Ruby Lead", query_conditions: "ruby", status: "pending")
      result = described_class.new(search: search)

      expect(result.search).to eq(search)
    end
  end
end
