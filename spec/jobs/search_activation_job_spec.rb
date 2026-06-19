# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchActivationJob, type: :job do
  include FactoryBot::Syntax::Methods

  describe "#perform" do
    let(:search) { create(:search) }
    let(:active_target)   { create(:target, :active) }
    let(:inactive_target) { create(:target, :inactive) }

    before do
      # Переносимо allow всередину before блоку
      allow(SearchActivator).to receive(:call).and_return(true)
    end

    context "when search campaign exists" do
      before do
        create(:prompt, search: search, target: active_target)
        create(:prompt, search: search, target: inactive_target)
      end

      it "calls SearchActivator with active target ids" do
        described_class.new.perform(search.id)

        expect(SearchActivator).to have_received(:call).with(
          search,
          [active_target.id]
        )
      end
    end

    context "when search campaign does not exist" do
      it "safely returns without calling activator" do
        described_class.new.perform(999_999)

        expect(SearchActivator).not_to have_received(:call)
      end
    end
  end
end
