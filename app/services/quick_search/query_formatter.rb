# frozen_string_literal: true

module QuickSearch
  class QueryFormatter
    BOOLEAN_OPERATORS = %w[OR AND NOT].freeze
    DORK_OPERATORS = %w[
      site tld from inurl allinurl intitle allintitle intext allintext
      filetype ext after before cache related define
    ].freeze

    def self.call(query)
      new(query).call
    end

    def initialize(query)
      @query = query.to_s.gsub(/\s+/, " ").strip
    end

    def call
      return "" if @query.empty?

      tokenize.map { |token| format_token(token) }.join(" ")
    end

    private

    def tokenize
      dork_operators = Regexp.union(DORK_OPERATORS)
      @query.scan(/(?:#{dork_operators}):"[^"]*"|"[^"]*"|\(|\)|[^\s()]+/i)
    end

    def format_token(token)
      return token if quoted?(token) || %w[( )].include?(token)
      return token.upcase if BOOLEAN_OPERATORS.include?(token.upcase)
      return token if dork_operator?(token) || token.start_with?("/")

      %("#{token.delete('"')}")
    end

    def quoted?(token)
      token.start_with?('"') && token.end_with?('"') && token.length >= 2
    end

    def dork_operator?(token)
      operator, value = token.split(":", 2)
      value.present? && DORK_OPERATORS.include?(operator.downcase)
    end
  end
end
