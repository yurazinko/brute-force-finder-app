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
  has_many :target_patterns, dependent: :destroy

  validates :name, presence: true
  validates :domain, uniqueness: { scope: :category_id }
  normalizes :domain, with: lambda { |value|
    return nil if value.blank?

    value.sub(%r{\Ahttps?://}, "")
         .delete_prefix("www.")
         .sub(%r{/+\z}, "")
         .downcase
  }

  scope :active, -> { where(is_active: true) }

  after_update_commit :sync_associated_prompts, if: :saved_change_to_domain?

  def persist_record(attributes)
    Targets::Persistor.call(self, attributes)
  end

  private

  def sync_associated_prompts
    Prompt.update_queries_for_target(self)
  end
end
