# frozen_string_literal: true

module Targets
  class PatternConfigurationService
    def self.call(...) = new(...).call

    def initialize(current_user:, pattern_params:, search: nil, result: nil, matched_target: nil)
      @user = current_user
      @search = search
      @result = result
      @matched_target = matched_target
      @params = pattern_params
    end

    def call
      target = resolve_target
      save_target_pattern(target)
      target
    end

    def self.call_direct(pattern_params:)
      new(current_user: nil, pattern_params: pattern_params).direct_call
    end

    def direct_call
      target = Target.find(@params[:target_id])
      path_pattern = @params[:path_pattern]

      if path_pattern.present? && path_pattern != "/"
        target.target_patterns.find_or_create_by!(path_pattern: path_pattern) do |tp|
          tp.is_active = true
        end
      end
      target
    end

    private

    def resolve_target
      target_id = @params[:target_id] || @matched_target&.id

      if target_id.blank?
        create_target_from_result
      else
        Target.find(target_id)
      end
    end

    def create_target_from_result
      domain = URI.parse(@result.url).host&.sub(Utils::UrlNormalizer::WWW_PREFIX, "")

      category = resolve_category

      category.targets.find_or_create_by!(domain: domain) do |t|
        t.name = domain.split(".").first.capitalize
        t.is_active = true
        t.allow_query_strings = ActiveModel::Type::Boolean.new.cast(@params[:allow_query_strings].to_i)
      end
    end

    def resolve_category
      category_id = @params[:category_id]
      category_name = @params[:category_name]

      if category_id.present?
        @user.categories.find(category_id)
      elsif category_name.present?
        @user.categories.find_or_create_by!(name: category_name.strip)
      else
        raise(ActiveRecord::RecordInvalid, Target.new.tap { |t| t.errors.add(:category, "can't be blank") })
      end
    end

    def save_target_pattern(target)
      path_pattern = @params[:path_pattern]
      return if path_pattern.blank? || path_pattern == "/"

      target_pattern = TargetPattern.find_or_initialize_by(target_id: target.id, path_pattern: path_pattern)
      target_pattern.is_active = true
      target_pattern.save!
    end
  end
end
