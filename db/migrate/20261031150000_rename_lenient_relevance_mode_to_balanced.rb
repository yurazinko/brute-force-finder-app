# frozen_string_literal: true

class RenameLenientRelevanceModeToBalanced < ActiveRecord::Migration[8.1]
  def up
    say_with_time "Rename lenient search relevance mode to balanced" do
      execute <<~SQL
        UPDATE searches
        SET relevance_mode = 'balanced'
        WHERE relevance_mode = 'lenient'
      SQL
    end
  end

  def down
    say_with_time "Restore legacy lenient search relevance mode" do
      execute <<~SQL
        UPDATE searches
        SET relevance_mode = 'lenient'
        WHERE relevance_mode = 'balanced'
      SQL
    end
  end
end
