class OptimizeResultsAndTargets < ActiveRecord::Migration[8.1]
  def change
    add_index :results, :created_at
  end
end
