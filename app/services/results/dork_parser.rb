# frozen_string_literal: true

module Results
  class DorkParser
    STOP_WORDS = %w[or and not in on at to for of with by is are be].freeze
    TOKEN_PATTERN = /"([^"]+)"|([^\s,;]+)/
    SEARCH_OPERATORS = %w[
      site tld from inurl allinurl intitle allintitle intext allintext
      filetype ext after before cache related define
    ].freeze

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
      cursor = 0

      text.to_enum(:scan, /\(([^()]*)\)/).each do
        match = Regexp.last_match
        groups.concat(groups_from_clause(text[cursor...match.begin(0)]))
        groups.concat(groups_from_clause(match[1]))
        cursor = match.end(0)
      end

      groups.concat(groups_from_clause(text[cursor..]))
      groups.reject(&:empty?)
    end

    private

    def sanitize_query(text)
      operator_pattern = Regexp.union(SEARCH_OPERATORS)
      text.dup
          .gsub(/\b(?:#{operator_pattern}):(?:"[^"]*"|'[^']*'|[^\s]+)/i, " ")
          .gsub(%r{/\w+}, " ")
    end

    def groups_from_clause(clause_text)
      return [] if clause_text.blank?

      tokens = clause_text.to_enum(:scan, TOKEN_PATTERN).map do
        match = Regexp.last_match
        [match[1] || match[2], !match[1].nil?]
      end

      groups = []
      alternatives = []
      expecting_or_term = false

      tokens.each_with_index do |(token, quoted), index|
        operator = quoted ? nil : token.upcase

        if operator == "OR"
          expecting_or_term = true
          next
        end

        if %w[AND NOT].include?(operator)
          flush_alternatives(groups, alternatives)
          expecting_or_term = false
          next
        end

        next if !quoted && STOP_WORDS.include?(token.downcase)

        next_token = tokens[index + 1]
        next_is_or = next_token && !next_token[1] && next_token[0].casecmp("OR").zero?

        if expecting_or_term || next_is_or
          alternatives << token
          expecting_or_term = false
          flush_alternatives(groups, alternatives) unless next_is_or
        else
          groups << [token]
        end
      end

      flush_alternatives(groups, alternatives)
      groups
    end

    def flush_alternatives(groups, alternatives)
      return if alternatives.empty?

      groups << alternatives.uniq
      alternatives.clear
    end
  end
end
