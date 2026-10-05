# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::UrlMatcher, type: :service do
  describe ".matches?" do
    subject(:matches?) { described_class.matches?(url, target) }

    let(:target) { build(:target, domain: target_domain) }

    context "when testing domain and path matching logic" do
      context "with target domain only (no path in target)" do
        let(:target_domain) { "indeed.com" }

        it "returns true when URL host matches target host and has a path" do
          expect(described_class.matches?("https://indeed.com/viewjob?id=1", target)).to be true
        end

        it "returns true when URL is a subdomain of target host" do
          expect(described_class.matches?("https://uk.indeed.com/jobs", target)).to be true
        end

        it "returns false when URL host does not match target host" do
          expect(described_class.matches?("https://linkedin.com/jobs", target)).to be false
        end
      end

      context "with target domain AND path" do
        let(:target_domain) { "indeed.com/viewjob" }

        it "returns true when both host and path match" do
          expect(described_class.matches?("https://indeed.com/viewjob?id=1", target)).to be true
        end

        it "returns true when URL path starts with target path prefix" do
          expect(described_class.matches?("https://indeed.com/viewjob/123/details", target)).to be true
        end

        it "returns false when host matches but path differs" do
          expect(described_class.matches?("https://indeed.com/cmp/company-name", target)).to be false
        end

        it "returns false when path matches but host differs" do
          expect(described_class.matches?("https://otherdomain.com/viewjob", target)).to be false
        end
      end
    end

    context "when handling edge cases and normalization" do
      context "with www prefix" do
        let(:target_domain) { "www.indeed.com/viewjob" }

        it "normalizes www in target domain and matches URL without www" do
          expect(described_class.matches?("https://indeed.com/viewjob/123", target)).to be true
        end

        it "normalizes www in URL and matches target domain without www" do
          target.domain = "indeed.com/viewjob"
          expect(described_class.matches?("https://www.indeed.com/viewjob/123", target)).to be true
        end
      end

      context "with protocol prefixes in target domain" do
        let(:target_domain) { "https://indeed.com/viewjob" }

        it "strips protocol from target domain before matching" do
          expect(described_class.matches?("https://indeed.com/viewjob?id=123", target)).to be true
        end
      end

      context "when target or target domain is blank" do
        let(:target_domain) { nil }

        it "returns true when target domain is nil" do
          expect(described_class.matches?("https://indeed.com/viewjob", target)).to be true
        end

        it "returns true when target is nil" do
          expect(described_class.matches?("https://indeed.com/viewjob", nil)).to be true
        end
      end

      context "when URL is invalid or malformed" do
        let(:target_domain) { "indeed.com" }

        it "returns false on invalid URI parsing error" do
          expect(described_class.matches?("http://:invalid_url", target)).to be false
        end
      end
    end
  end
end
