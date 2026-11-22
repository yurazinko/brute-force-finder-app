# frozen_string_literal: true

module QuickSearch
  class ResultSorter
    def self.call(results)
      Array(results).sort_by do |result|
        status = read(result, :verification_status).to_s
        captcha = status == "unverified_captcha" ? 1 : 0
        score = read(result, :relevance_score).to_i
        matched_count = Array(read(result, :matched_keywords)).size

        [captcha, -score, -matched_count]
      end
    end

    def self.read(result, key)
      result.respond_to?(key) ? result.public_send(key) : result[key.to_s] || result[key]
    end
    private_class_method :read
  end
end
