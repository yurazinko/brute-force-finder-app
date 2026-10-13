# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::UrlHighlighter, type: :service do
  let(:user) { User.create!(email: "highlighter_test@example.com", password: "password123") }
  let(:category) { Category.create!(name: "Tech", user: user) }
  let(:target) { Target.create!(category: category, name: "Example Target", domain: "example.com") }
  let(:search) { Search.create!(user: user, title: "Search", query_conditions: "ruby", status: "completed") }

  let(:view_context) { ActionController::Base.new.view_context }

  describe ".call" do
    subject { described_class.call(result, view_context) }

    context "when url is blank or nil" do
      let(:result) { Result.new(url: nil, search: search) }

      it "returns the blank url as is" do
        expect(subject).to be_nil
      end
    end

    context "when URI is invalid" do
      let(:result) { Result.new(url: "not a valid uri :::", search: search) }

      it "escapes and returns the invalid url string safely" do
        expect(subject).to eq("not a valid uri :::")
      end
    end

    context "when target or target domain is missing" do
      let(:result) { Result.new(url: "https://unknown-site.org/page", search: search) }

      it "returns escaped full url parts without target highlighting" do
        expect(subject).to include("https://")
        expect(subject).to include("unknown-site.org")
        expect(subject).to include("/page")
      end
    end

    context "when target matches host and paths" do
      let!(:pattern) do
        TargetPattern.create!(
          target: target,
          path_pattern: "/blog/*",
          is_active: true
        )
      end

      let(:result) do
        Result.create!(
          search: search,
          url: "https://sub.example.com/blog/ruby-guide?q=1",
          url_hash: Digest::SHA256.hexdigest("https://sub.example.com/blog/ruby-guide?q=1"),
          title: "Blog Post",
          content: "Content"
        )
      end

      it "highlights target domain and matching path pattern correctly" do
        output = subject

        expect(output).to include("sub")
        expect(output).to include("example.com")
        expect(output).to include("text-indigo-400 font-semibold")
        expect(output).to include("/blog/ruby-guide")
        expect(output).to include("?q=1")
      end
    end

    context "when path matches a static substring pattern" do
      let!(:pattern) do
        TargetPattern.create!(
          target: target,
          path_pattern: "/about-us",
          is_active: true
        )
      end

      let(:result) do
        Result.create!(
          search: search,
          url: "https://example.com/about-us",
          url_hash: Digest::SHA256.hexdigest("https://example.com/about-us"),
          title: "About",
          content: "About us page"
        )
      end

      it "highlights the exact substring match" do
        output = subject
        expect(output).to include("text-indigo-400 font-semibold")
        expect(output).to include("/about-us")
      end
    end
  end
end
