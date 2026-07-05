# frozen_string_literal: true

module SearchCampaigns
  class DorkRandomizer
    SITE_OPERATOR_REGEX = /(site:\S+)/
    BRACKET_CONTENT_REGEX = /\(([^)]+)\)/
    OR_DELIMITER_REGEX = /\s+OR\s+/

    def self.perform(query)
      return query if query.blank?

      site_operator, clean_query = extract_site_operator(query)
      bracket_blocks = shuffle_bracket_keywords(clean_query)

      return query if bracket_blocks.empty?

      shuffled_query = rebuild_query_body(bracket_blocks)
      combine_results(site_operator, shuffled_query)
    end

    private_class_method def self.extract_site_operator(query)
      return [nil, query] unless query.match?(SITE_OPERATOR_REGEX)

      site_operator = query.match(SITE_OPERATOR_REGEX)[1]
      clean_query = query.sub(SITE_OPERATOR_REGEX, "").strip

      [site_operator, clean_query]
    end

    private_class_method def self.shuffle_bracket_keywords(query)
      query.scan(BRACKET_CONTENT_REGEX).map do |(pure_text)|
        keywords = pure_text.split(OR_DELIMITER_REGEX)
        "(#{keywords.shuffle.join(' OR ')})"
      end
    end

    private_class_method def self.rebuild_query_body(bracket_blocks)
      first_block = bracket_blocks.first
      remaining_blocks = bracket_blocks[1..] || []

      "#{first_block} #{remaining_blocks.shuffle.join(' ')}".strip
    end

    private_class_method def self.combine_results(site_operator, shuffled_query)
      if site_operator
        "#{site_operator} #{shuffled_query}".squish
      else
        shuffled_query.squish
      end
    end
  end
end
