class CreateTargetPatterns < ActiveRecord::Migration[8.1]
  def change
    create_table :target_patterns do |t|
      t.references :target, null: false, foreign_key: true
      t.string :path_pattern, null: false
      t.boolean :is_active, default: true, null: false

      t.timestamps
    end

    add_index :target_patterns, [:target_id, :path_pattern], unique: true, name: "index_target_patterns_on_target_and_pattern"

    reversible do |dir|
      dir.up do
        execute <<-SQL
          SELECT id, domain FROM targets WHERE domain LIKE '%/%';
        SQL

        Target.where("domain LIKE ?", "%/%").find_each do |target|
          full_domain = target.domain.to_s
          clean_domain, *path_parts = full_domain.split("/")
          path_suffix = "/#{path_parts.join("/")}"

          target.update_column(:domain, clean_domain)
          target.target_patterns.create!(path_pattern: path_suffix, is_active: true)
        end
      end
    end
  end
end
