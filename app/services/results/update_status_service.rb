# frozen_string_literal: true

module Results
  class UpdateStatusService
    def initialize(result:, status:)
      @result = result
      @status = status
    end

    def call
      ActiveRecord::Base.transaction do
        @result.update!(status: @status)

        if @status != "unread"
          Result.where(url_hash: @result.url_hash).update_all(acknowledged: true, updated_at: Time.current)
        end
      end

      true
    rescue ActiveRecord::RecordInvalid
      false
    end
  end
end
