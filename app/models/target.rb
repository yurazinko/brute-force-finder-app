# frozen_string_literal: true

# == Schema Information
#
# Table name: targets
#
#  id                  :bigint           not null, primary key
#  allow_query_strings :boolean          default(FALSE), not null
#  domain              :string
#  is_active           :boolean          default(TRUE)
#  name                :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  category_id         :bigint           not null
#
# Indexes
#
#  index_targets_on_category_id  (category_id)
#  index_targets_on_domain       (domain)
#
# Foreign Keys
#
#  fk_rails_...  (category_id => categories.id)
#
class Target < ApplicationRecord
  belongs_to :category
  has_many :prompts, dependent: :destroy

  validates :name, presence: true
  validates :domain, uniqueness: { scope: :category_id }
  normalizes :domain, with: ->(value) { value.presence }

  scope :active, -> { where(is_active: true) }

  after_update_commit :sync_associated_prompts, if: :saved_change_to_domain?

  def self.top_by_prompts_count(limit_number)
    joins(:prompts)
      .left_joins(:category)
      .select("targets.name, targets.domain, COUNT(DISTINCT prompts.id) as prompts_count")
      .group("targets.id, targets.name, targets.domain")
      .order(prompts_count: :desc)
      .limit(limit_number)
  end

  def self.prompts_distribution_map
    joins(:prompts).group("targets.name").order(count_all: :desc).limit(5).count
  end

  private

  def sync_associated_prompts
    Prompt.update_queries_for_target(self)
  end
end
