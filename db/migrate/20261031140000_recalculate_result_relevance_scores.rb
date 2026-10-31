# frozen_string_literal: true

require "json"

class RecalculateResultRelevanceScores < ActiveRecord::Migration[8.1]
  MAX_SCORE = 100
  FIRST_GROUP_PENALTY = 150
  CAPTCHA_SCORE_FLOOR = 25
  BATCH_SIZE = 500
  STOP_WORDS = %w[or and not in on at to for of with by is are be].freeze

  def up
    recalculate_scores(apply_new_rules: true)
  end

  def down
    # Restore the ranker behavior from before this migration: percentage of
    # matched groups with the first-group penalty, without the Balanced
    # primary-only clamp or CAPTCHA score floor.
    recalculate_scores(apply_new_rules: false)
  end

  private

  def recalculate_scores(apply_new_rules:)
    say_with_time("Recalculate stored result relevance scores") do
      connection.select_all("SELECT id, query_conditions, relevance_mode FROM searches ORDER BY id").each do |search|
        groups = parse_groups(search["query_conditions"])
        next if groups.empty?

        recalculate_search_results(search, groups, apply_new_rules:)
      end
    end
  end

  def recalculate_search_results(search, groups, apply_new_rules:)
    last_id = 0

    loop do
      results = connection.select_all(<<~SQL.squish)
        SELECT id, matched_keywords, verification_status
        FROM results
        WHERE search_id = #{search.fetch("id").to_i}
          AND id > #{last_id}
        ORDER BY id
        LIMIT #{BATCH_SIZE}
      SQL
      break if results.empty?

      score_rows = results.map do |result|
        flags = matched_group_flags(groups, parse_json_array(result["matched_keywords"]))
        matched_count = flags.count(true)
        first_matched = flags.first == true

        score = (matched_count.fdiv(groups.size) * MAX_SCORE).round
        score -= FIRST_GROUP_PENALTY unless first_matched

        if apply_new_rules
          if search["relevance_mode"] != "strict" && first_matched &&
             groups.size > 1 && !flags.drop(1).any?
            score = 0
          end

          if result["verification_status"] == "unverified_captcha" &&
             captcha_candidate?(flags, search["relevance_mode"])
            score = [score, CAPTCHA_SCORE_FLOOR].max
          end
        end

        [result["id"].to_i, score]
      end

      update_score_batch(score_rows)
      last_id = results.last["id"].to_i
    end
  end

  def update_score_batch(score_rows)
    return if score_rows.empty?

    case_sql = score_rows.map { |id, score| "WHEN #{id} THEN #{score}" }.join(" ")
    ids_sql = score_rows.map(&:first).join(",")

    connection.execute(<<~SQL.squish)
      UPDATE results
      SET relevance_score = CASE id #{case_sql} ELSE relevance_score END
      WHERE id IN (#{ids_sql})
    SQL
  end

  def parse_groups(query_text)
    return [] if query_text.blank?

    text = query_text.to_s
                 .gsub(/\b(site|tld|from):[^\s]+/i, "")
                 .gsub(%r{/\w+}, "")
    groups = []

    text.gsub!(/\(([^)]+)\)/) do
      extracted = extract_tokens_from_clause(Regexp.last_match(1))
      groups << extracted if extracted.any?
      ""
    end

    extract_tokens_from_clause(text).each { |keyword| groups << [keyword] }
    groups.reject(&:empty?)
  end

  def extract_tokens_from_clause(clause_text)
    return [] if clause_text.blank?

    quoted_phrases = clause_text.scan(/"([^"]+)"/).flatten
    clean_unquoted = clause_text.gsub(/"[^"]+"/, "").gsub(/\b(OR|AND|NOT)\b/i, " ")
    unquoted_words = clean_unquoted.split(/\s+/)
                                     .reject { |word| word.length < 2 || STOP_WORDS.include?(word.downcase) }

    (quoted_phrases + unquoted_words).uniq
  end

  def parse_json_array(value)
    parsed = value.is_a?(String) ? JSON.parse(value) : value
    Array(parsed)
  rescue JSON::ParserError, TypeError
    []
  end

  def matched_group_flags(groups, matched_keywords)
    normalized_matches = matched_keywords.map { |keyword| keyword.to_s.downcase }
    groups.map do |group|
      group.any? { |keyword| normalized_matches.include?(keyword.downcase) }
    end
  end

  def captcha_candidate?(flags, relevance_mode)
    return false unless flags.first

    relevance_mode == "strict" || flags.size <= 1 || flags.drop(1).any?
  end
end
