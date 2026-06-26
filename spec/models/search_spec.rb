# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      search = described_class.new(title: "Ruby Jobs", query_conditions: "(ruby)", status: "pending")
      expect(search).to be_valid
    end

    it "is invalid without a title" do
      search = described_class.new(title: nil)
      search.valid?
      expect(search.errors[:title]).to include("can't be blank")
    end

    it "is invalid without query_conditions" do
      search = described_class.new(query_conditions: nil)
      search.valid?
      expect(search.errors[:query_conditions]).to include("can't be blank")
    end

    it "is invalid with an incorrect status" do
      search = described_class.new(status: "invalid_status")
      search.valid?
      expect(search.errors[:status]).to include("is not included in the list")
    end
  end

  describe "associations" do
    it "has many prompts with dependent destroy" do
      association = described_class.reflect_on_association(:prompts)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end

    it "has many targets through prompts" do
      association = described_class.reflect_on_association(:targets)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:through]).to eq(:prompts)
    end

    it "has many results with dependent destroy" do
      association = described_class.reflect_on_association(:results)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end
  end

  describe "#activate_search!" do
    let(:category) { Category.create!(name: "Tech Platforms") }
    let!(:target_lever) { Target.create!(category: category, name: "Lever", domain: "lever.co", is_active: true) }
    let!(:target_greenhouse) { Target.create!(category: category, name: "Greenhouse", domain: "greenhouse.io", is_active: true) }
    let!(:target_inactive) { Target.create!(category: category, name: "Broken Site", domain: "broken.com", is_active: false) }

    let(:search) do
      described_class.create!(
        title: "Ruby Backend",
        query_conditions: '(ruby OR "rails") (backend)',
        status: "pending"
      )
    end

    context "when providing valid and active target IDs" do
      let(:target_ids) { [target_lever.id, target_greenhouse.id, target_inactive.id] }

      it "creates prompts only for active targets and updates search status" do
        expect { search.activate_search!(target_ids) }
          .to change(search.prompts, :count).by(2)

        expect(search.reload.status).to eq("processing")

        lever_prompt = search.prompts.find_by(target: target_lever)
        expect(lever_prompt.full_query_text).to eq('site:lever.co (ruby OR "rails") (backend)')
        expect(lever_prompt.status).to eq("pending")
      end

      it "returns true upon successful execution" do
        expect(search.activate_search!(target_ids)).to be_truthy
      end
    end

    context "when a query string already exists (idempotency check)" do
      let(:target_ids) { [target_lever.id] }

      before do
        # Створюємо промпт саме для ЦЬОГО пошуку, щоб спровокувати конфлікт
        search.prompts.create!(
          target: target_lever,
          full_query_text: "site:lever.co #{search.query_conditions}",
          status: "failed"
        )
      end

      it "does not create a duplicate prompt and resets status to pending via upsert" do
        expect { search.activate_search!(target_ids) }
          .not_to change(Prompt, :count)

        expect(search.reload.status).to eq("processing")

        existing_prompt = search.prompts.find_by(target: target_lever)
        expect(existing_prompt.status).to eq("pending")
      end
    end

    context "when validation or database failure occurs inside the activator" do
      let(:target_ids) { [target_lever.id] }

      before do
        allow(Prompt).to receive(:upsert_all).and_raise(ActiveRecord::ActiveRecordError.new("DB Corruption"))
        allow(Rails.logger).to receive(:error)
      end

      it "fails gracefully, changes zero prompts and preserves old search status" do
        expect { search.activate_search!(target_ids) }
          .not_to change(Prompt, :count)

        expect(search.reload.status).to eq("pending")
      end

      it "logs the specific critical failure error message" do
        search.activate_search!(target_ids)
        expect(Rails.logger).to have_received(:error).with(
          /\[SearchCampaigns::Activator\] Critical failure for Search##{search.id}/
        )
      end

      it "returns false instead of crashing the pipeline" do
        expect(search.activate_search!(target_ids)).to be_falsy
      end
    end
  end
end
