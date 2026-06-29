# frozen_string_literal: true

class Search < ApplicationRecord
  ALLOWED_STATUSES = %w[pending processing completed failed].freeze
  ALLOWED_TIME_FRAMES = [nil, "day", "week", "month", "year"].freeze

  has_many :prompts, dependent: :destroy
  has_many :targets, through: :prompts
  has_many :results, dependent: :destroy

  normalizes :time_frame, with: ->(value) { value.presence }

  validates :title, :query_conditions, presence: true
  validates :status, inclusion: { in: ALLOWED_STATUSES }
  validates :time_frame, inclusion: { in: ALLOWED_TIME_FRAMES }, allow_nil: true

  def activate_search!(target_ids)
    SearchCampaigns::Activator.call(self, target_ids)
  end

  def calculate_counters(scoped_results = results)
    SearchCampaigns::CountersCalculator.new(self).calculate(scoped_results)
  end

  def counts_for_index(raw_counts)
    SearchCampaigns::CountersCalculator.new(self).for_index(raw_counts)
  end
end
