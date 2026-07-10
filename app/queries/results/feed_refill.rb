# frozen_string_literal: true

module Results
  class FeedRefill
    def self.next_card(base_scope:, removed_id:, current_dom_count:, options:)
      return nil if current_dom_count.zero?

      query = Results::Index.new(base_scope, options)
      full_scope = query.call

      target_offset = current_dom_count - 1
      next_record = full_scope.offset(target_offset).first

      next_record = full_scope.offset(target_offset + 1).first if next_record && next_record.id == removed_id.to_i

      next_record
    end
  end
end
