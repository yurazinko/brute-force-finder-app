# frozen_string_literal: true

class Search < ApplicationRecord
  has_many :prompts, dependent: :destroy
  has_many :targets, through: :prompts
  has_many :results, dependent: :destroy

  normalizes :time_frame, with: ->(value) { value.presence }

  validates :title, :query_conditions, presence: true
  validates :status, inclusion: { in: %w[pending processing completed failed] }

  validates :time_frame, inclusion: { in: [nil, "day", "week", "month", "year"] }, allow_nil: true

  def activate_search!(target_ids)
    SearchCampaigns::Activator.call(self, target_ids)
  end

  def calculate_counters(scoped_results = results)
    raw_counts = scoped_results.group(:status, :acknowledged).count
    show_ack   = show_acknowledged?

    counters = { unread: 0, interesting: 0, watched: 0, garbage: 0 }

    raw_counts.each do |(status, acknowledged), count|
      case status
      when "unread"
        counters[:unread] += count if !acknowledged || show_ack
      when "interesting", "watched", "garbage"
        counters[status.to_sym] += count
      end
    end

    counters[:all_clean] = counters[:unread] + counters[:interesting] + counters[:watched]
    counters
  end

  def counts_for_index(raw_counts)
    show_ack  = show_acknowledged?
    search_id = id.to_i

    unread_unack    = raw_counts[[search_id, "unread", false]] || 0
    unread_ack      = show_ack ? (raw_counts[[search_id, "unread", true]] || 0) : 0
    unread          = unread_unack + unread_ack

    interesting     = (raw_counts[[search_id, "interesting",
                                   false]] || 0) + (raw_counts[[search_id, "interesting", true]] || 0)
    garbage         = (raw_counts[[search_id, "garbage",
                                   false]] || 0) + (raw_counts[[search_id, "garbage", true]] || 0)
    watched         = (raw_counts[[search_id, "watched",
                                   false]] || 0) + (raw_counts[[search_id, "watched", true]] || 0)

    {
      unread: unread,
      interesting: interesting,
      watched: watched,
      garbage: garbage,
      all_clean: unread + interesting + watched
    }
  end
end
