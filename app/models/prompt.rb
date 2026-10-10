# frozen_string_literal: true

# == Schema Information
#
# Table name: prompts
#
#  id              :bigint           not null, primary key
#  error_message   :text
#  full_query_text :string           not null
#  status          :string           default("pending")
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  search_id       :bigint           not null
#  target_id       :bigint
#
# Indexes
#
#  index_global_prompts_on_search_and_query  (search_id,full_query_text) UNIQUE WHERE (target_id IS NULL)
#  index_prompts_on_search_id                (search_id)
#  index_prompts_on_search_target_and_query  (search_id,target_id,full_query_text) UNIQUE WHERE (target_id IS NOT NULL)
#  index_prompts_on_target_id                (target_id)
#
# Foreign Keys
#
#  fk_rails_...  (search_id => searches.id)
#  fk_rails_...  (target_id => targets.id)
#
class Prompt < ApplicationRecord
  belongs_to :search
  belongs_to :target, optional: true

  validates :status, presence: true, inclusion: { in: %w[pending active failed success] }

  validates :full_query_text, presence: true

  scope :active, -> { joins(:target).where(targets: { is_active: true }) }

  before_validation :generate_full_query_text, if: -> { full_query_text.blank? && search.present? && target.present? }

  def self.update_queries_for_target(target)
    where(target_id: target.id).includes(:search).find_each do |prompt|
      new_query = "site:#{target.domain} #{prompt.search.query_conditions}"

      prompt.update_columns(full_query_text: new_query, updated_at: Time.current)
    rescue ActiveRecord::RecordNotUnique
      prompt.destroy
    end
  end

  private

  def generate_full_query_text
    self.full_query_text = "site:#{target.domain} #{search.query_conditions}"
  end
end
