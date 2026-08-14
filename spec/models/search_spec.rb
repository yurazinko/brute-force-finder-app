# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search, type: :model do
  let(:user) { create(:user) }

  describe "validations" do
    it "is valid with valid attributes" do
      search = described_class.new(user: user, title: "Ruby Jobs", query_conditions: "(ruby)", status: "pending")
      expect(search).to be_valid
    end

    it "is invalid without a title" do
      search = described_class.new(user: user, title: nil)
      expect(search).not_to be_valid
      expect(search.errors[:title]).to include("can't be blank")
    end

    it "is invalid without query_conditions" do
      search = described_class.new(user: user, query_conditions: nil)
      expect(search).not_to be_valid
      expect(search.errors[:query_conditions]).to include("can't be blank")
    end

    it "is invalid with an incorrect status" do
      search = described_class.new(user: user, status: "invalid_status")
      expect(search).not_to be_valid
      expect(search.errors[:status]).to include("is not included in the list")
    end

    it "is valid with allowed time frames" do
      %w[day week month year].each do |frame|
        search = described_class.new(user: user, title: "A", query_conditions: "B", status: "pending", time_frame: frame)
        expect(search).to be_valid
      end
    end

    it "is invalid with an incorrect time frame" do
      search = described_class.new(user: user, title: "A", query_conditions: "B", status: "pending", time_frame: "century")
      expect(search).not_to be_valid
      expect(search.errors[:time_frame]).to include("is not included in the list")
    end
  end

  describe "normalization" do
    it "normalizes blank time_frame strings to nil" do
      search = described_class.create!(user: user, title: "A", query_conditions: "B", status: "pending", time_frame: " ")
      expect(search.time_frame).to be_nil
    end
  end

  describe "associations" do
    it "belongs to user" do
      association = described_class.reflect_on_association(:user)
      expect(association.macro).to eq(:belongs_to)
    end

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

  describe "counter calculations" do
    let(:search) { described_class.create!(user: user, title: "Metrics", query_conditions: "ruby", status: "pending", show_acknowledged: false) }

    before do
      search.results.create!(title: "R1", url: "https://a.com/1", url_hash: "1", status: "unread", acknowledged: false)
      search.results.create!(title: "R2", url: "https://a.com/2", url_hash: "2", status: "unread", acknowledged: true)
      search.results.create!(title: "R3", url: "https://a.com/3", url_hash: "3", status: "interesting", acknowledged: false)
      search.results.create!(title: "R4", url: "https://a.com/4", url_hash: "4", status: "watched", acknowledged: true)
      search.results.create!(title: "R5", url: "https://a.com/5", url_hash: "5", status: "garbage", acknowledged: false)
    end

    describe "#calculate_counters" do
      context "when show_acknowledged is false" do
        it "calculates metrics excluding acknowledged unread links" do
          counters = search.calculate_counters

          expect(counters[:unread]).to eq(1)
          expect(counters[:interesting]).to eq(1)
          expect(counters[:watched]).to eq(1)
          expect(counters[:garbage]).to eq(1)
          expect(counters[:all_clean]).to eq(3) # unread(1) + interesting(1) + watched(1)
        end
      end

      context "when show_acknowledged is true" do
        it "includes acknowledged unread links into the unread counter" do
          search.update!(show_acknowledged: true)
          counters = search.calculate_counters

          expect(counters[:unread]).to eq(2)
          expect(counters[:all_clean]).to eq(4)
        end
      end
    end

    describe "#counts_for_index" do
      let(:raw_counts) do
        {
          [search.id, "unread", false] => 2,
          [search.id, "unread", true] => 3,
          [search.id, "interesting", false] => 1,
          [search.id, "interesting", true] => 1,
          [search.id, "watched", false] => 4,
          [search.id, "garbage", true] => 5
        }
      end

      it "aggregates raw DB counts grouped by search_id, status and acknowledgment" do
        counts = search.counts_for_index(raw_counts)

        expect(counts[:unread]).to eq(2)
        expect(counts[:interesting]).to eq(2)
        expect(counts[:watched]).to eq(4)
        expect(counts[:garbage]).to eq(5)
        expect(counts[:all_clean]).to eq(8) # 2 + 2 + 4
      end

      it "includes acknowledged unread items if show_acknowledged is enabled" do
        search.update!(show_acknowledged: true)
        counts = search.counts_for_index(raw_counts)

        expect(counts[:unread]).to eq(5) # unack(2) + ack(3)
        expect(counts[:all_clean]).to eq(11)
      end
    end
  end

  describe "#activate_search!" do
    let(:category) { Category.create!(name: "Tech Platforms") }
    let!(:target_lever) { Target.create!(category: category, name: "Lever", domain: "lever.co", is_active: true) }
    let!(:target_greenhouse) { Target.create!(category: category, name: "Greenhouse", domain: "greenhouse.io", is_active: true) }
    let!(:target_inactive) { Target.create!(category: category, name: "Broken Site", domain: "broken.com", is_active: false) }

    let(:search) do
      described_class.create!(
        user: user,
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
