# frozen_string_literal: true

require "rails_helper"

RSpec.describe Results::ResultFilter, type: :service do
  let(:user) { User.create!(email: "test@example.com", password: "password") }
  let(:category) { Category.create!(name: "General", user: user) }
  let(:target) { create(:target, domain: "example.com", category: category) }
  let(:prompt) { instance_double("Prompt", target: target, full_query_text: 'site:example.com (ruby OR "ruby on rails")') }
  let(:target_configs) { { "example.com" => true } }

  let(:valid_result) do
    {
      "url" => "https://example.com/jobs/dev?jk=c632099926f119ae&src=search",
      "title" => "Senior Developer",
      "content" => "We are looking for an experienced software engineer."
    }
  end

  let(:rank_result) { instance_double("RelevanceRanker::Result", valid?: true) }

  subject { described_class.new(valid_result, prompt, target_configs) }

  describe "#valid?" do
    context "when URL is blank" do
      let(:valid_result) { { "url" => "", "title" => "Test", "content" => "Test" } }

      it "returns false without delegating to RelevanceRanker" do
        expect(Results::RelevanceRanker).not_to receive(:call)
        expect(subject.valid?).to be false
      end
    end

    context "when URL does not match the target domain" do
      let(:valid_result) { { "url" => "https://other-domain.com/job", "title" => "Ruby", "content" => "Ruby" } }

      it "returns false without delegating to RelevanceRanker" do
        expect(Results::RelevanceRanker).not_to receive(:call)
        expect(subject.valid?).to be false
      end
    end

    context "when URL and domain match target" do
      before do
        allow(Results::DorkParser).to receive(:parse_groups).with(prompt.full_query_text).and_return([%w[ruby]])
      end

      it "delegates to RelevanceRanker and returns its validity status" do
        expected_snippet = "https://example.com/jobs/dev?jk=c632099926f119ae&src=search Senior Developer We are looking for an experienced software engineer."

        expect(Results::RelevanceRanker).to receive(:call)
          .with(valid_result, expected_snippet, [%w[ruby]], valid_result["url"])
          .and_return(rank_result)

        expect(subject.valid?).to be true
        expect(subject.rank_result).to eq(rank_result)
      end

      context "when RelevanceRanker considers result invalid" do
        let(:rank_result) { instance_double("RelevanceRanker::Result", valid?: false) }

        it "returns false" do
          allow(Results::RelevanceRanker).to receive(:call).and_return(rank_result)
          expect(subject.valid?).to be false
        end
      end
    end

    context "when URL is on a regional subdomain with query parameters" do
      let(:indeed_target) { create(:target, domain: "indeed.com", category: category) }
      let(:indeed_prompt) { instance_double("Prompt", target: indeed_target, full_query_text: "site:indeed.com ruby") }
      let(:target_configs) { { "indeed.com" => true } }

      let(:valid_result) do
        {
          "url" => "https://pl.indeed.com/viewjob?jk=c632099926f119ae",
          "title" => "Ruby Developer PL",
          "content" => "Job description in Poland"
        }
      end

      subject { described_class.new(valid_result, indeed_prompt, target_configs) }

      before do
        allow(Results::DorkParser).to receive(:parse_groups).with(indeed_prompt.full_query_text).and_return([%w[ruby]])
      end

      it "successfully validates regional subdomain URLs with parameters" do
        allow(Results::RelevanceRanker).to receive(:call).and_return(rank_result)
        expect(subject.valid?).to be true
      end
    end
  end

  describe "extracted component dependencies" do
    describe "Results::DorkParser" do
      it "correctly parses boolean groups and standalone words" do
        query = 'site:apply.workable.com tld:io (ruby OR "ruby on rails") /date (krakow OR cracow) developer'
        groups = Results::DorkParser.parse_groups(query)

        expect(groups).to contain_exactly(
          ["ruby on rails", "ruby"],
          %w[krakow cracow],
          ["developer"]
        )
      end

      it "handles lowercased operators like or/and/not without treating them as keywords" do
        query = "(react or vue) and senior"
        groups = Results::DorkParser.parse_groups(query)

        expect(groups).to contain_exactly(
          %w[react vue],
          ["senior"]
        )
      end
    end

    describe "Results::UrlMatcher with query parameters and subdomains" do
      let(:path_target) { create(:target, domain: "indeed.com", category: category) }

      before do
        TargetPattern.create!(target: path_target, path_pattern: "/viewjob", is_active: true)
      end

      it "matches URLs with query parameters against target path" do
        url = "https://www.indeed.com/viewjob?jk=c632099926f119ae&from=serp"
        expect(Results::UrlMatcher.matches?(url, path_target)).to be true
      end

      it "matches regional subdomains with query parameters against target domain and path" do
        url = "https://pl.indeed.com/viewjob?jk=c632099926f119ae"
        expect(Results::UrlMatcher.matches?(url, path_target)).to be true
      end

      it "returns false for invalid query parameters or non-matching paths on subdomains" do
        url = "https://pl.indeed.com/account/login?next=/viewjob"
        expect(Results::UrlMatcher.matches?(url, path_target)).to be false
      end

      it "handles malformed or complex query parameters without throwing errors" do
        url = "https://pl.indeed.com/viewjob?jk=123&tags[]=ruby&tags[]=rails#section"
        expect { Results::UrlMatcher.matches?(url, path_target) }.not_to raise_error
        expect(Results::UrlMatcher.matches?(url, path_target)).to be true
      end
    end
  end
end
