module SearchCampaigns
  class DorkRandomizer
    def self.perform(query)
      return query if query.blank?

      site_operator = nil

      if query =~ /(site:\S+)/
        site_operator = ::Regexp.last_match(1)
        query = query.sub(/(site:\S+)/, "").strip
      end

      bracket_blocks = query.scan(/\([^)]+\)/).map do |block_content|
        pure_text = block_content[1..-2]
        keywords = pure_text.split(/\s+OR\s+/)
        "(#{keywords.shuffle.join(' OR ')})"
      end

      return query if bracket_blocks.empty?

      first_block = bracket_blocks.first
      remaining_blocks = bracket_blocks[1..] || []

      shuffled_tail = remaining_blocks.shuffle.join(" ")

      combined_query = "#{first_block} #{shuffled_tail}".strip

      if site_operator
        "#{site_operator} #{combined_query}".squish
      else
        combined_query.squish
      end
    end
  end
end
