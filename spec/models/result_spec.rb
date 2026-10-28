# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: results
#
#  id                  :bigint           not null, primary key
#  acknowledged        :boolean          default(FALSE), not null
#  content             :text
#  engine              :string
#  matched_keywords    :jsonb            not null
#  relevance_score     :integer          default(0), not null
#  status              :string           default("unread"), not null
#  target_domain       :string
#  target_pattern      :string
#  title               :string
#  url                 :string           not null
#  url_hash            :string           not null
#  verification_status :string           default("pending"), not null
#  viewed_at           :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  search_id           :bigint           not null
#  target_id           :bigint
#
# Indexes
#
#  idx_results_analytics                           (search_id,status,acknowledged)
#  idx_results_content_trgm                        (content gin_trgm_ops) USING gin
#  idx_results_title_trgm                          (title gin_trgm_ops) USING gin
#  idx_results_url_trgm                            (url gin_trgm_ops) USING gin
#  index_results_on_created_at                     (created_at)
#  index_results_on_relevance_score                (relevance_score)
#  index_results_on_search_id                      (search_id)
#  index_results_on_search_id_and_relevance_score  (search_id,relevance_score)
#  index_results_on_search_id_and_status           (search_id,status)
#  index_results_on_search_id_and_target_id        (search_id,target_id)
#  index_results_on_search_id_and_url_hash         (search_id,url_hash) UNIQUE
#  index_results_on_search_status_ack_relevance    (search_id,status,acknowledged,relevance_score)
#  index_results_on_target_domain                  (target_domain)
#  index_results_on_target_id                      (target_id)
#  index_results_on_url_hash                       (url_hash)
#  index_results_on_verification_status            (verification_status)
#
# Foreign Keys
#
#  fk_rails_...  (search_id => searches.id)
#  fk_rails_...  (target_id => targets.id)
#
RSpec.describe Result, type: :model do
  let(:user) { User.create!(username: "test@example.com", password: "password") }
  let(:category) { Category.create!(name: "General", user: user) }
  let(:search) { Search.create!(title: "Ruby Lead", query_conditions: "ruby", user: user) }

  let!(:target_rails) { Target.create!(category: category, name: "Ruby on Rails", domain: "rubyonrails.org") }
  let!(:target_github) { Target.create!(category: category, name: "GitHub", domain: "github.com") }
  let!(:target_old) { Target.create!(category: category, name: "Old Domain", domain: "old-domain.com") }

  describe ".top_domains_efficiency" do
    before do
      Result.create!(
        search: search,
        target: target_rails,
        status: "unread",
        relevance_score: 5,
        url: "https://rubyonrails.org/1",
        url_hash: "hash_rails_1",
        created_at: 2.days.ago
      )
      Result.create!(
        search: search,
        target: target_rails,
        status: "unread",
        relevance_score: 3,
        url: "https://rubyonrails.org/2",
        url_hash: "hash_rails_2",
        created_at: 3.days.ago
      )

      Result.create!(
        search: search,
        target: target_rails,
        status: "unread",
        relevance_score: 0,
        url: "https://rubyonrails.org/zero",
        url_hash: "hash_rails_zero",
        created_at: 1.day.ago
      )

      Result.create!(
        search: search,
        target: target_github,
        status: "garbage",
        relevance_score: 2,
        url: "http://github.com/1",
        url_hash: "hash_github_1",
        created_at: 5.days.ago
      )

      Result.create!(
        search: search,
        target: target_old,
        status: "unread",
        relevance_score: 10,
        url: "https://old-domain.com/1",
        url_hash: "hash_old_1",
        created_at: 40.days.ago
      )

      Result.create!(
        search: search,
        target: nil,
        status: "unread",
        relevance_score: 15,
        url: "https://orphan-domain.com/1",
        url_hash: "hash_orphan_1",
        created_at: 1.day.ago
      )
    end

    it "aggregates efficiency metrics strictly for targets, filtering out unlinked, zero-relevance, and old records" do
      stats = described_class.top_domains_efficiency(since: 30.days.ago, limit: 5)

      rails_stat = stats.find { |r| r[:domain] == "rubyonrails.org" }
      github_stat = stats.find { |r| r[:domain] == "github.com" }
      old_stat = stats.find { |r| r[:domain] == "old-domain.com" }
      orphan_stat = stats.find { |r| r[:domain] == "orphan-domain.com" }

      expect(rails_stat[:relevant_results_count]).to eq(2)
      expect(rails_stat[:total_relevance_score]).to eq(8)
      expect(rails_stat[:average_relevance_score]).to eq(4.0)

      expect(github_stat[:relevant_results_count]).to eq(1)
      expect(github_stat[:total_relevance_score]).to eq(2)
      expect(github_stat[:average_relevance_score]).to eq(2.0)

      expect(old_stat).to be_nil
      expect(orphan_stat).to be_nil
    end
  end
end
