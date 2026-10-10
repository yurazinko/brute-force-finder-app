# frozen_string_literal: true

# == Schema Information
#
# Table name: searches
#
#  id                :bigint           not null, primary key
#  query_conditions  :text
#  show_acknowledged :boolean          default(FALSE), not null
#  status            :string           default("pending")
#  time_frame        :string
#  title             :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  user_id           :bigint
#
# Indexes
#
#  index_searches_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Search < ApplicationRecord
  ALLOWED_STATUSES = %w[pending processing completed failed paused].freeze
  ALLOWED_TIME_FRAMES = [nil, "day", "week", "month", "year"].freeze

  belongs_to :user

  has_many :prompts, dependent: :destroy
  has_many :targets, through: :prompts
  has_many :results, dependent: :destroy

  normalizes :time_frame, with: ->(value) { value.presence }

  validates :title, :query_conditions, presence: true
  validates :status, inclusion: { in: ALLOWED_STATUSES }
  validates :time_frame, inclusion: { in: ALLOWED_TIME_FRAMES }, allow_nil: true

  def target_ids=(ids)
    prompts.delete_all if will_save_change_to_query_conditions?
    super
  end

  def paused?
    status == "paused"
  end

  def pause!
    update!(status: "paused")
  end

  def resume!
    update!(status: "pending")
  end

  def force_complete!
    update!(status: "completed")
  end

  def activate_search!(target_ids)
    SearchCampaigns::Activator.call(self, target_ids)
  end
end
