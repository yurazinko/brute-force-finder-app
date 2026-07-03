require "rails_helper"

RSpec.describe SearchCampaigns::DorkRandomizer, type: :service do
  describe ".perform" do
    let(:original_dork) do
      'site:glassdoor.com/job-listing (ruby OR "ruby on rails") (backend OR fullstack OR developer) (worldwide OR anywhere)'
    end

    subject(:shuffled_dork) { described_class.perform(original_dork) }

    it "preserves the site: operator with its full path" do
      expect(shuffled_dork).to include("site:glassdoor.com/job-listing")
    end

    it "retains the total number of logical groups in parentheses" do
      shuffled_count = shuffled_dork.scan(/\([^)]+\)/).size
      expect(shuffled_count).to eq(3)
    end

    it "does not lose or corrupt any keywords or operators" do
      original_tokens = original_dork.gsub(/[()]/, "").split.sort
      shuffled_tokens = shuffled_dork.gsub(/[()]/, "").split.sort

      expect(shuffled_tokens).to eq(original_tokens)
    end

    it 'preserves the integrity of quoted phrases like "ruby on rails"' do
      expect(shuffled_dork).to include('"ruby on rails"')
    end

    it "randomizes both internal words and the position of the site: operator" do
      results = Array.new(10) { described_class.perform(original_dork) }

      expect(results.uniq.size).to be > 1
    end

    it "gracefully handles strings without a site: operator" do
      no_site_dork = "(ruby OR rails) (remote OR anywhere)"
      result = described_class.perform(no_site_dork)

      expect(result.scan(/\([^)]+\)/).size).to eq(2)
    end
  end
end
