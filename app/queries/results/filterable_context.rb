# frozen_string_literal: true

module Results
  module FilterableContext
    private

    def cast_boolean(value)
      ActiveModel::Type::Boolean.new.cast(value) || false
    end

    def unread_acknowledged_conditions(options, search_show_acknowledged: false)
      show_ack = if options[:show_acknowledged].nil?
                   search_show_acknowledged
                 else
                   cast_boolean(options[:show_acknowledged])
                 end

      show_ack ? [false, true] : [false]
    end
  end
end
