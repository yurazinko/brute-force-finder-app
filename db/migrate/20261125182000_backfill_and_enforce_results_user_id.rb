# frozen_string_literal: true

class BackfillAndEnforceResultsUserId < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  BATCH_SIZE = 10_000
  NOT_NULL_CHECK = "results_user_id_not_null"

  def up
    with_rls_bypass_if_possible do
      backfill_user_ids!
    end

    add_and_validate_foreign_key!
    enforce_not_null!
    add_tenant_index!
    replace_results_policy!
  end

  def down
    execute <<~SQL
      ALTER POLICY result_user_isolation ON public.results
      USING (
        EXISTS (
          SELECT 1
            FROM public.searches
           WHERE searches.id = results.search_id
             AND searches.user_id = public.current_user_id()
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1
            FROM public.searches
           WHERE searches.id = results.search_id
             AND searches.user_id = public.current_user_id()
        )
      )
    SQL

    remove_index :results, name: :index_results_on_user_id_and_search_id, algorithm: :concurrently, if_exists: true
    remove_foreign_key :results, column: :user_id, if_exists: true
    change_column_null :results, :user_id, true
  end

  private

  def with_rls_bypass_if_possible
    if role_has_bypass_or_super?
      yield
      return
    end

    results_had_force_rls = table_force_rls?("results")
    searches_had_force_rls = table_force_rls?("searches")

    execute "ALTER TABLE public.results NO FORCE ROW LEVEL SECURITY" if results_had_force_rls
    execute "ALTER TABLE public.searches NO FORCE ROW LEVEL SECURITY" if searches_had_force_rls

    yield
  rescue ActiveRecord::StatementInvalid => e
    raise unless e.message.include?("must be owner") || e.message.include?("permission denied")

    raise "Migration role lacks BYPASSRLS and table ownership to read/backfill RLS-protected rows. " \
          "Run migrations as table owner/superuser or grant BYPASSRLS to the migration role."
  ensure
    execute "ALTER TABLE public.results FORCE ROW LEVEL SECURITY" if results_had_force_rls
    execute "ALTER TABLE public.searches FORCE ROW LEVEL SECURITY" if searches_had_force_rls
  end

  def role_has_bypass_or_super?
    role = select_one(<<~SQL)
      SELECT rolbypassrls, rolsuper
        FROM pg_catalog.pg_roles
       WHERE rolname = current_user
    SQL

    role && (%w[t true].include?(role["rolbypassrls"].to_s) || %w[t true].include?(role["rolsuper"].to_s))
  end

  def table_force_rls?(table_name)
    val = select_value(<<~SQL)
      SELECT relforcerowsecurity
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relname = #{connection.quote(table_name)}
    SQL

    %w[t true].include?(val.to_s)
  end

  def backfill_user_ids!
    loop do
      ids = select_values(<<~SQL)
        SELECT id
          FROM public.results
         WHERE user_id IS NULL
         ORDER BY id
         LIMIT #{BATCH_SIZE}
      SQL
      break if ids.empty?

      safe_ids = ids.map { |id| Integer(id.to_s, 10) }.join(",")
      execute <<~SQL
        UPDATE public.results AS results
           SET user_id = searches.user_id
          FROM public.searches AS searches
         WHERE results.id IN (#{safe_ids})
           AND searches.id = results.search_id
      SQL

      unresolved = select_value(<<~SQL).to_i
        SELECT COUNT(*)
          FROM public.results
         WHERE id IN (#{safe_ids})
           AND user_id IS NULL
      SQL
      next if unresolved.zero?

      raise "#{unresolved} results have no resolvable searches.user_id; fix orphan/legacy rows before retrying this migration."
    end

    remaining = select_value("SELECT COUNT(*) FROM public.results WHERE user_id IS NULL").to_i
    raise "Results user_id backfill incomplete: #{remaining} rows remain." if remaining.positive?
  end

  def add_and_validate_foreign_key!
    unless foreign_key_exists?(:results, :users, column: :user_id)
      add_foreign_key :results, :users, column: :user_id, validate: false
    end

    validate_foreign_key :results, :users
  end

  def enforce_not_null!
    unless check_constraint_exists?(:results, name: NOT_NULL_CHECK)
      add_check_constraint :results, "user_id IS NOT NULL", name: NOT_NULL_CHECK, validate: false
    end

    validate_check_constraint :results, name: NOT_NULL_CHECK
    change_column_null :results, :user_id, false
    remove_check_constraint :results, name: NOT_NULL_CHECK
  end

  def add_tenant_index!
    index_name = "index_results_on_user_id_and_search_id"
    valid = select_value(<<~SQL)
      SELECT index_state.indisvalid
        FROM pg_catalog.pg_class AS index_class
        JOIN pg_catalog.pg_index AS index_state ON index_state.indexrelid = index_class.oid
       WHERE index_class.relname = #{connection.quote(index_name)}
    SQL

    execute "DROP INDEX CONCURRENTLY IF EXISTS public.#{index_name}" if valid.to_s.in?(%w[f false])

    add_index :results, %i[user_id search_id],
              name: index_name,
              algorithm: :concurrently,
              if_not_exists: true
  end

  def replace_results_policy!
    execute <<~SQL
      ALTER POLICY result_user_isolation ON public.results
      USING (user_id = public.current_user_id())
      WITH CHECK (user_id = public.current_user_id())
    SQL
  end
end
