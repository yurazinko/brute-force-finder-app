# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::UrlMatcher, type: :service do
  let(:user) { User.create!(email: "test@example.com", password: "password") }
  let(:category) { Category.create!(name: "General", user: user) }
  let(:target) { create(:target, domain: target_domain, category: category) }
  let(:target_domain) { "indeed.com" }

  describe ".matches?" do
    subject(:matches?) { described_class.matches?(url, target) }

    context "when testing basic domain matching" do
      let(:target_domain) { "indeed.com" }

      it "returns true when URL host matches target host exactly" do
        url = "https://indeed.com/jobs"
        expect(described_class.matches?(url, target)).to be true
      end

      it "returns true when URL is a regional or sub-subdomain of the target host" do
        url = "https://pl.indeed.com/viewjob?id=123"
        expect(described_class.matches?(url, target)).to be true
      end

      it "returns false when URL host does not match target host" do
        url = "https://linkedin.com/jobs"
        expect(described_class.matches?(url, target)).to be false
      end

      it "returns false when URL host is a partial suffix mismatch (e.g. fakeindeed.com)" do
        url = "https://fakeindeed.com/jobs"
        expect(described_class.matches?(url, target)).to be false
      end
    end

    context "when testing active target patterns (paths)" do
      let(:target_domain) { "github.com" }

      context "with exact path patterns" do
        before do
          TargetPattern.create!(target: target, path_pattern: "/features/actions", is_active: true)
        end

        it "returns true when exact path matches" do
          url = "https://github.com/features/actions"
          expect(described_class.matches?(url, target)).to be true
        end

        it "returns false when path differs" do
          url = "https://github.com/features/packages"
          expect(described_class.matches?(url, target)).to be false
        end
      end

      context "with wildcard path patterns (*)" do
        before do
          TargetPattern.create!(target: target, path_pattern: "/issues/*", is_active: true)
        end

        it "returns true for a simple wildcard match" do
          url = "https://github.com/issues/999"
          expect(described_class.matches?(url, target)).to be true
        end

        it "returns true for deeply nested paths under the wildcard (with slashes)" do
          url = "https://github.com/issues/999/comments/12"
          expect(described_class.matches?(url, target)).to be true
        end

        it "returns false if the wildcard base path is missing" do
          url = "https://github.com/pulls/999"
          expect(described_class.matches?(url, target)).to be false
        end
      end

      context "with multi-wildcard patterns (e.g. /*/jobs/*)" do
        before do
          TargetPattern.create!(target: target, path_pattern: "/*/jobs/*", is_active: true)
        end

        it "returns true when multiple dynamic segments match" do
          url = "https://github.com/en-us/jobs/backend-dev"
          expect(described_class.matches?(url, target)).to be true
        end

        it "returns false when the structure breaks" do
          url = "https://github.com/jobs/backend-dev" # Бракує першого сегмента
          expect(described_class.matches?(url, target)).to be false
        end
      end

      context "with inactive patterns" do
        before do
          TargetPattern.create!(target: target, path_pattern: "/issues/*", is_active: false)
        end

        it "ignores inactive patterns and allows everything if no active patterns remain" do
          url = "https://github.com/pulls/123"
          expect(described_class.matches?(url, target)).to be true
        end
      end
    end

    context "when handling edge cases and normalization" do
      context "with www prefix variants" do
        let(:target_domain) { "www.indeed.com" }

        it "normalizes www in target domain and matches URL without www" do
          url = "https://indeed.com/viewjob/123"
          expect(described_class.matches?(url, target)).to be true
        end

        it "normalizes www in URL and matches target domain without www" do
          target.update!(domain: "indeed.com")
          url = "https://www.indeed.com/viewjob/123"
          expect(described_class.matches?(url, target)).to be true
        end
      end

      context "with protocol prefixes in target domain (http/https)" do
        let(:target_domain) { "https://indeed.com" }

        it "strips protocol from target domain and matches securely" do
          url = "https://indeed.com/viewjob?id=123"
          expect(described_class.matches?(url, target)).to be true
        end
      end

      context "when trailing slashes exist in target domain" do
        let(:target_domain) { "indeed.com/" }

        it "strips trailing slashes correctly" do
          url = "https://indeed.com/viewjob"
          expect(described_class.matches?(url, target)).to be true
        end
      end

      context "when target or target domain is blank/nil" do
        let(:target_domain) { nil }

        it "returns false when target domain is nil" do
          url = "https://indeed.com/viewjob"
          expect(described_class.matches?(url, target)).to be false
        end

        it "returns false when target itself is nil" do
          url = "https://indeed.com/viewjob"
          expect(described_class.matches?(url, nil)).to be false
        end
      end

      context "when URL is invalid or malformed" do
        let(:target_domain) { "indeed.com" }

        it "rescues URI::InvalidURIError and returns false" do
          url = "http://:invalid_url_with_colons"
          expect(described_class.matches?(url, target)).to be false
        end

        it "returns false for blank URLs" do
          expect(described_class.matches?("", target)).to be false
          expect(described_class.matches?(nil, target)).to be false
        end
      end

      context "with complex query parameters and fragments" do
        let(:target_domain) { "indeed.com" }

        it "ignores query strings and anchors during host/path evaluation" do
          url = "https://indeed.com/path?query=1&param=2#anchor"
          expect(described_class.matches?(url, target)).to be true
        end
      end
    end
  end

  describe ".matched_pattern" do
    let(:target_domain) { "example.com" }
    let!(:active_pattern) { TargetPattern.create!(target: target, path_pattern: "/blog/*", is_active: true) }

    it "returns the matching TargetPattern object when conditions are met" do
      url = "https://example.com/blog/ruby-guide"
      expect(described_class.matched_pattern(url, target)).to eq(active_pattern)
    end

    it "returns nil when no pattern matches" do
      url = "https://example.com/shop/item-1"
      expect(described_class.matched_pattern(url, target)).to be nil
    end

    it "returns nil if target or domain is blank" do
      blank_target = build(:target, domain: nil)
      url = "https://example.com/blog/ruby-guide"
      expect(described_class.matched_pattern(url, blank_target)).to be nil
    end
  end
end
