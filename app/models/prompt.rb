# frozen_string_literal: true

class Prompt < ApplicationRecord
  belongs_to :search
  belongs_to :target

  validates :status, inclusion: { in: %w[pending active failed success] }
  validates :full_query_text, presence: true
end
