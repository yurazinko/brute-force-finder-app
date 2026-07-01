# frozen_string_literal: true

class Prompt < ApplicationRecord
  belongs_to :search
  belongs_to :target

  validates :status, presence: true, inclusion: { in: %w[pending active failed success] }

  validates :full_query_text, presence: true

  scope :active, -> { joins(:target).where(targets: { is_active: true }) }

  before_validation :generate_full_query_text, if: -> { full_query_text.blank? && search.present? && target.present? }

  private

  def generate_full_query_text
    self.full_query_text = "site:#{target.domain} #{search.query_conditions}"
  end
end
