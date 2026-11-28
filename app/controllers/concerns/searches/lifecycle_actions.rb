# frozen_string_literal: true

module Searches
  module LifecycleActions
    extend ActiveSupport::Concern

    def activate
      activated = @search.activate_search!(params[:target_ids] || [])
      @search.reload if activated
      respond_to_activation(activated)
    end

    def toggle_pause
      paused = @search.paused?
      paused ? @search.resume! : @search.pause!
      respond_to_lifecycle_change(paused ? "Campaign resumed." : "Campaign paused.")
    end

    def complete
      @search.force_complete!
      respond_to_lifecycle_change("Campaign completed.")
    end

    private

    def respond_to_activation(activated)
      message = activation_message(activated)
      respond_to do |format|
        format.html { redirect_to search_path(@search), **message }
        format.turbo_stream do
          flash.now[message.key?(:notice) ? :notice : :alert] = message.values.first
          render_activation_stream(activated)
        end
      end
    end

    def activation_message(activated)
      if activated
        { notice: "Scraping pipeline successfully initialized!" }
      else
        { alert: "Failed to activate search. Check system logs." }
      end
    end

    def render_activation_stream(activated)
      if activated
        render "searches/update", status: :ok
      else
        render turbo_stream: turbo_stream.replace("flash-container", partial: "layouts/flash")
      end
    end

    def respond_to_lifecycle_change(message)
      respond_to do |format|
        format.html { redirect_back_or_to search_path(@search), notice: message }
        format.turbo_stream do
          flash.now[:notice] = message
          render "searches/update", status: :ok
        end
      end
    end
  end
end
