# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuickSearch::QueryFormatter, type: :service do
  describe ".call" do
    it "quotes each unquoted term and leaves OR operators between the terms" do
      expect(described_class.call("мостиська OR городок")).to eq('"мостиська" OR "городок"')
    end

    it "preserves an explicitly quoted multi-word phrase as one term" do
      expect(described_class.call('"мостиська городок"')).to eq('"мостиська городок"')
    end

    it "quotes terms inside boolean groups without quoting operators or search dorks" do
      query = 'site:example.com (ruby OR "ruby on rails") developer'

      expect(described_class.call(query)).to eq('site:example.com ( "ruby" OR "ruby on rails" ) "developer"')
    end

    it "keeps a quoted phrase attached to a dork operator" do
      expect(described_class.call('intitle:"ruby jobs" developer'))
        .to eq('intitle:"ruby jobs" "developer"')
    end

    it "returns an empty string for blank queries" do
      expect(described_class.call("  ")).to eq("")
    end
  end
end
