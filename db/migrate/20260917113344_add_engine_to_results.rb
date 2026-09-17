class AddEngineToResults < ActiveRecord::Migration[8.1]
  def change
    add_column :results, :engine, :string
  end
end
