class AddTargetDomainAndTargetPatternToResults < ActiveRecord::Migration[8.1]
  def change
    add_column :results, :target_domain, :string
    add_column :results, :target_pattern, :string
    add_index :results, :target_domain
  end
end
