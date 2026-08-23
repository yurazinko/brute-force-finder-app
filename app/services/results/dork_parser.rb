# frozen_string_literal: true

# app/services/results/dork_parser.rb
module Results
  class DorkParser
    STOP_WORDS = %w[or and not in on at to for of with by is are be].freeze

    def self.parse_groups(query_text)
      new(query_text).parse_groups
    end

    def initialize(query_text)
      @query_text = query_text.to_s
    end

    def parse_groups
      return [] if @query_text.blank?

      text = sanitize_query(@query_text)
      groups = []

      text.gsub!(/\(([^)]+)\)/) do
        extracted = extract_tokens_from_clause(Regexp.last_match(1))
        groups << extracted if extracted.any?
        ""
      end

      remaining = extract_tokens_from_clause(text)
      remaining.each { |kw| groups << [kw] }

      groups.reject(&:empty?)
    end

    private

    def sanitize_query(text)
      text.dup
          .gsub(/\b(site|tld|from):[^\s]+/i, "")
          .gsub(%r{/\w+}, "")
    end

    def extract_tokens_from_clause(clause_text)
      return [] if clause_text.blank?

      quoted_phrases = clause_text.scan(/"([^"]+)"/).flatten
      clean_unquoted = clause_text.gsub(/"[^"]+"/, "")
                                  .gsub(/\b(OR|AND|NOT)\b/i, " ")

      unquoted_words = clean_unquoted.split(/\s+/)
                                     .reject { |w| w.length < 2 || STOP_WORDS.include?(w.downcase) }

      (quoted_phrases + unquoted_words).uniq
    end
  end
end
