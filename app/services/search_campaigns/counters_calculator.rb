# frozen_string_literal: true

module SearchCampaigns
  class CountersCalculator
    def initialize(search)
      @search = search
      @show_ack = search.show_acknowledged?
    end

    def calculate(scoped_results)
      raw_counts = scoped_results.group(:status, :acknowledged).count

      counters = initialize_counters
      aggregate_raw_counts(raw_counts, counters)

      counters[:all_clean] = counters[:unread] + counters[:interesting] + counters[:watched]
      counters
    end

    def for_index(raw_counts)
      search_id = @search.id.to_i

      unread = sum_unread_for_index(raw_counts, search_id)
      interesting = sum_status_for_index(raw_counts, search_id, "interesting")
      watched = sum_status_for_index(raw_counts, search_id, "watched")
      garbage = sum_status_for_index(raw_counts, search_id, "garbage")

      {
        unread: unread, interesting: interesting, watched: watched, garbage: garbage,
        all_clean: unread + interesting + watched
      }
    end

    private

    def initialize_counters
      { unread: 0, interesting: 0, watched: 0, garbage: 0 }
    end

    def aggregate_raw_counts(raw_counts, counters)
      raw_counts.each do |(status, acknowledged), count|
        case status
        when "unread"
          counters[:unread] += count if !acknowledged || @show_ack
        when "interesting", "watched", "garbage"
          counters[status.to_sym] += count
        end
      end
    end

    def sum_unread_for_index(raw_counts, search_id)
      unack = raw_counts[[search_id, "unread", false]] || 0
      ack = @show_ack ? (raw_counts[[search_id, "unread", true]] || 0) : 0
      unack + ack
    end

    def sum_status_for_index(raw_counts, search_id, status)
      (raw_counts[[search_id, status, false]] || 0) + (raw_counts[[search_id, status, true]] || 0)
    end
  end
end
