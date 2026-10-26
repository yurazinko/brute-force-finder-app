# frozen_string_literal: true

require "rails_helper"

RSpec.describe TargetActivationJob, type: :job do
  let(:user) { create(:user) }
  let(:category) { Category.create!(name: "SaaS", user: user) }
  let!(:target) { Target.create!(category: category, name: "Lever", domain: "lever.co", is_active: true) }
  let!(:search1) { Search.create!(user: user, title: "Search 1", query_conditions: "ruby", status: "pending") }
  let!(:search2) { Search.create!(user: user, title: "Search 2", query_conditions: "elixir", status: "pending") }

  describe "#perform" do
    it "synchronizes prompts for selected searches and removes unselected ones" do
      target.prompts.create!(search: search2, full_query_text: "site:lever.co elixir")

      described_class.new.perform(target.id, [search1.id], user.id)

      expect(target.prompts.count).to eq(1)
      prompt = target.prompts.first
      expect(prompt.search).to eq(search1)
      expect(prompt.full_query_text).to eq("site:lever.co ruby")
    end

    it "does nothing if target is not found" do
      expect { described_class.new.perform(-999, [search1.id], user.id) }.not_to change(Prompt, :count)
    end
  end
end
