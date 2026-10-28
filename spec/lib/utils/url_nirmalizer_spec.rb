# frozen_string_literal: true

require "rails_helper"

RSpec.describe Utils::UrlNormalizer do
  describe ".normalize" do
    context "with valid URLs" do
      it "downcases scheme and domain, strips www, preserves path case, and keeps query when configured" do
        url = "HTTPS://WWW.Example.com/Path/To/Resource?q=1"
        normalized = described_class.normalize(url, target_configs: { "example.com" => true })

        expect(normalized).to eq("https://example.com/Path/To/Resource?q=1")
      end

      it "handles URLs without www prefix correctly" do
        url = "http://example.com/jobs/123"
        normalized = described_class.normalize(url)

        expect(normalized).to eq("http://example.com/jobs/123")
      end

      it "strips query parameters by default when target_configs is empty or does not allow them" do
        url = "https://example.com/path?utm_source=twitter&ref=123"
        normalized = described_class.normalize(url, target_configs: { "example.com" => false })

        expect(normalized).to eq("https://example.com/path")
      end

      it "keeps query parameters when target_configs allows them for the exact domain" do
        url = "https://example.com/search?q=ruby"
        configs = { "example.com" => true }
        normalized = described_class.normalize(url, target_configs: configs)

        expect(normalized).to eq("https://example.com/search?q=ruby")
      end

      it "keeps query parameters when target_configs allows them for a parent domain (subdomain matching)" do
        url = "https://jobs.example.com/search?q=ruby"
        configs = { "example.com" => true }
        normalized = described_class.normalize(url, target_configs: configs)

        expect(normalized).to eq("https://jobs.example.com/search?q=ruby")
      end

      it "strips query parameters if target_configs matches but allow_query is false" do
        url = "https://jobs.example.com/search?q=ruby"
        configs = { "example.com" => false }
        normalized = described_class.normalize(url, target_configs: configs)

        expect(normalized).to eq("https://jobs.example.com/search")
      end
    end

    context "with edge cases and invalid inputs" do
      it "returns nil for blank, nil, or whitespace-only URLs" do
        expect(described_class.normalize(nil)).to be_nil
        expect(described_class.normalize("")).to be_nil
        expect(described_class.normalize("   ")).to be_nil
      end

      it "returns nil for malformed or invalid URIs" do
        expect(described_class.normalize("http://:invalid_uri")).to be_nil
        expect(described_class.normalize("not-a-url")).to be_nil
      end

      it "returns nil if host or scheme is missing" do
        expect(described_class.normalize("/just/a/path")).to be_nil
        expect(described_class.normalize("example.com/path")).to be_nil
      end
    end
  end

  describe ".extract_domain" do
    it "strips www. prefix if present" do
      expect(described_class.extract_domain("www.example.com")).to eq("example.com")
    end

    it "leaves domain intact if www. is absent" do
      expect(described_class.extract_domain("example.com")).to eq("example.com")
      expect(described_class.extract_domain("sub.example.com")).to eq("sub.example.com")
    end

    it "returns nil for blank hosts" do
      expect(described_class.extract_domain(nil)).to be_nil
      expect(described_class.extract_domain("")).to be_nil
    end
  end

  describe ".clean_domain_string" do
    it "cleans protocols, paths, and www prefixes, and downcases the result" do
      expect(described_class.clean_domain_string("https://WWW.Example.com/path/to/page")).to eq("example.com")
      expect(described_class.clean_domain_string("http://sub.domain.org/")).to eq("sub.domain.org")
      expect(described_class.clean_domain_string("www.github.com")).to eq("github.com")
    end

    it "handles blank or nil strings safely" do
      expect(described_class.clean_domain_string(nil)).to be_nil
      expect(described_class.clean_domain_string("")).to be_nil
    end
  end

  describe ".hash" do
    it "produces identical hashes for URLs differing only by www prefix or scheme case" do
      url_with_www = "HTTPS://WWW.Example.com/jobs/1"
      url_without_www = "https://example.com/jobs/1"

      hash1 = described_class.hash(url_with_www)
      hash2 = described_class.hash(url_without_www)

      expect(hash1).to eq(hash2)
    end

    it "produces different hashes for URLs with different path cases (case-sensitive paths)" do
      url_lower = "https://example.com/Jobs/1"
      url_upper = "https://example.com/JOBS/1"

      expect(described_class.hash(url_lower)).not_to eq(described_class.hash(url_upper))
    end

    it "returns nil if the URL cannot be normalized" do
      expect(described_class.hash("invalid-url")).to be_nil
      expect(described_class.hash(nil)).to be_nil
    end
  end
end
