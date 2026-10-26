# frozen_string_literal: true

module Targets
  class Persistor
    def self.call(target, attributes) = new(target, attributes).call

    def initialize(target, attributes)
      @target = target
      @search_ids = attributes[:search_ids]
      @category_id = attributes[:category_id]
      @target_attributes = attributes.except(:category_id, :search_ids)
    end

    def call
      ActiveRecord::Base.transaction do
        @target.category = Category.find(@category_id) if @category_id.present?
        @target.assign_attributes(@target_attributes)
        @target.save!
      end

      if @search_ids&.compact_blank&.any?
        TargetActivationJob.perform_async(@target.id, @search_ids, @target.category.user_id)
      end

      true
    rescue ActiveRecord::RecordInvalid => e
      @target.errors.merge!(e.record.errors) unless e.record == @target
      false
    end
  end
end
