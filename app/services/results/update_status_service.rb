# frozen_string_literal: true

module Results
  class UpdateStatusService
    def initialize(result:, status:)
      @result = result
      @status = status
    end

    def call
      @result.update!(
        status: @status,
        acknowledged: @status != "unread"
      )

      true
    rescue ActiveRecord::RecordInvalid
      false
    end
  end
end
