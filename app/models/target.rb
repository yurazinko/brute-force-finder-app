# frozen_string_literal: true

class Target < ApplicationRecord
  belongs_to :category
  has_many :prompts, dependent: :destroy

  validates :name, :domain, presence: true
  validates :domain, uniqueness: true

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
