# frozen_string_literal: true

class ResultsFilterScope
  def self.call(scope, options = {})
    new(scope, options).apply
  end

  def initialize(scope, options)
    @scope = scope
    @options = options
  end

  def apply
    scoped = @scope
    scoped = filter_by_status(scoped)
    scoped = filter_by_time_frame(scoped)
    scoped = filter_by_keyword(scoped)
    scoped.order(sorting_order)
  end

  private

  def filter_by_status(scoped)
    status = @options[:status]
    if %w[garbage interesting watched].include?(status)
      scoped.where(status: status)
    else
      scoped.where(status: "unread", acknowledged: acknowledgement_filter)
    end
  end

  def filter_by_time_frame(scoped)
    case @options[:time_frame].to_s
    when "day"   then scoped.where(created_at: 1.day.ago.beginning_of_day..)
    when "week"  then scoped.where(created_at: 1.week.ago.beginning_of_day..)
    when "month" then scoped.where(created_at: 1.month.ago.beginning_of_day..)
    when "year"  then scoped.where(created_at: 1.year.ago.beginning_of_day..)
    else scoped
    end
  end

  def filter_by_keyword(scoped)
    query = @options[:keyword]
    return scoped if query.blank? || query.strip.length < 3

    sanitized = ActiveRecord::Base.sanitize_sql_like(query.strip)
    scoped.where("results.title ILIKE :q OR results.content ILIKE :q", q: "%#{sanitized}%")
  end

  def sorting_order
    {
      "created_asc" => { created_at: :asc },
      "updated_desc" => { updated_at: :desc },
      "updated_asc" => { updated_at: :asc }
    }.fetch(@options[:sort], { created_at: :desc })
  end

  def acknowledgement_filter
    ActiveModel::Type::Boolean.new.cast(@options[:show_acknowledged])
  end
end
