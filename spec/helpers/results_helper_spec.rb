# frozen_string_literal: true

require "rails_helper"

RSpec.describe ResultsHelper, type: :helper do
  let(:user) { User.create!(username: "test@example.com", password: "password") }
  let(:category) { Category.create!(name: "General", user: user) }
  let(:search) { create(:search, user: user) }
  let!(:target) { Target.create!(name: "GitHub", domain: "github.com", category: category) } # Змінено на let!

  describe "#highlight_target_domain" do
    context "when URL or target domain is blank" do
      it "returns original URL if url is blank" do
        result = Result.new(url: "", search: search)
        expect(helper.highlight_target_domain(result)).to eq("")
      end

      it "does NOT highlight the host with bold styling if no specific target matches" do
        result = Result.new(url: "https://unknown.com/page", search: search)
        output = helper.highlight_target_domain(result)

        expect(output).to include("unknown.com")
        expect(output).not_to include("font-bold")
      end
    end

    context "when URL is valid and matches target domain without patterns" do
      let!(:result) { Result.create!(search: search, url: "https://github.com/features/actions", url_hash: "hash_1") }

      it "highlights the target domain name" do
        html_output = helper.highlight_target_domain(result)

        expect(html_output).to include("github.com")
        expect(html_output).to include("font-bold")
      end
    end

    context "when URL is on a subdomain and matches target domain" do
      let!(:result) { Result.create!(search: search, url: "https://api.github.com/v1", url_hash: "hash_sub") }

      it "only highlights the matching target domain part, leaving the subdomain unhighlighted" do
        html_output = helper.highlight_target_domain(result)

        expect(html_output).to include("api.")
        expect(html_output).to include("github.com")
        expect(html_output).to match(%r{api\.?<span class="text-breeze-text font-bold">github\.com</span>})
      end
    end

    context "when URL matches target domain AND has an exact path pattern" do
      let!(:pattern) { TargetPattern.create!(target: target, path_pattern: "/features/actions", is_active: true) }
      let!(:result) { Result.create!(search: search, url: "https://github.com/features/actions", url_hash: "hash_2") }

      it "highlights both the domain part and the exact path pattern" do
        html_output = helper.highlight_target_domain(result)

        expect(html_output).to include("github.com")
        expect(html_output).to include("/features/actions")
        expect(html_output).to include("font-bold")
        expect(html_output).to include("text-indigo-400")
      end
    end

    context "when URL matches target domain AND has a wildcard path pattern (*)" do
      let!(:pattern) { TargetPattern.create!(target: target, path_pattern: "/issues/*", is_active: true) }
      let!(:result) { Result.create!(search: search, url: "https://github.com/issues/999", url_hash: "hash_3") }

      it "highlights the path matching the wildcard pattern" do
        html_output = helper.highlight_target_domain(result)

        expect(html_output).to include("github.com")
        expect(html_output).to include("/issues/999")
        expect(html_output).to include("text-indigo-400")
      end
    end

    context "when URL contains query parameters" do
      let!(:pattern) { TargetPattern.create!(target: target, path_pattern: "/search", is_active: true) }
      let!(:result) { Result.create!(search: search, url: "https://github.com/search?q=ruby", url_hash: "hash_4") }

      it "safely handles and preserves query strings without breaking highlighting" do
        html_output = helper.highlight_target_domain(result)

        expect(html_output).to include("github.com")
        expect(html_output).to include("?q=ruby")
      end
    end

    context "when URL is malformed/invalid" do
      it "rescues URI::InvalidURIError and returns safe escaped string" do
        result = Result.new(url: "https://github.com/invalid space url", search: search)

        expect do
          helper.highlight_target_domain(result)
        end.not_to raise_error
      end
    end
  end
end
