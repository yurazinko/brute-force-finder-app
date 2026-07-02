# frozen_string_literal: true

class Prompt < ApplicationRecord
  belongs_to :search
  belongs_to :target

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
