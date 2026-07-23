module Results
  class FeedRefill
    def self.next_card(base_scope:, removed_id:, current_dom_count:, options:)
      dom_count = current_dom_count.to_i

      dom_count = 20 if dom_count <= 0

      query = Results::Index.new(base_scope, options)
      full_scope = query.call

      target_offset = [dom_count - 1, 0].max

      full_scope.where.not(id: removed_id).offset(target_offset).first
    end
  end
end
