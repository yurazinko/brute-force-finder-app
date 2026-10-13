# frozen_string_literal: true

# == Schema Information
#
# Table name: target_patterns
#
#  id           :bigint           not null, primary key
#  is_active    :boolean          default(TRUE), not null
#  path_pattern :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  target_id    :bigint           not null
#
# Indexes
#
#  index_target_patterns_on_target_and_pattern  (target_id,path_pattern) UNIQUE
#  index_target_patterns_on_target_id           (target_id)
#
# Foreign Keys
#
#  fk_rails_...  (target_id => targets.id)
#
class TargetPattern < ApplicationRecord
  belongs_to :target

  validates :path_pattern, presence: true, uniqueness: { scope: :target_id }
  normalizes :path_pattern, with: ->(value) { value.presence&.start_with?("/") ? value : "/#{value}" }

  scope :active, -> { where(is_active: true) }
end
