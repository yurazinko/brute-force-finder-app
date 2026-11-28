# frozen_string_literal: true

class AddUserIdToResults < ActiveRecord::Migration[8.1]
  def up
    add_column :results, :user_id, :bigint

    execute <<~SQL
      CREATE OR REPLACE FUNCTION public.populate_results_user_id()
      RETURNS trigger
      LANGUAGE plpgsql
      SET search_path = pg_catalog, public
      AS $function$
      DECLARE
        search_owner_id bigint;
      BEGIN
        SELECT searches.user_id
          INTO search_owner_id
          FROM public.searches
         WHERE searches.id = NEW.search_id;

        IF search_owner_id IS NULL THEN
          RAISE EXCEPTION 'Cannot resolve tenant for result search_id %', NEW.search_id
            USING ERRCODE = '23503';
        END IF;

        IF NEW.user_id IS NOT NULL AND NEW.user_id <> search_owner_id THEN
          RAISE EXCEPTION 'Result tenant does not match search tenant'
            USING ERRCODE = '42501';
        END IF;

        NEW.user_id := search_owner_id;
        RETURN NEW;
      END;
      $function$;
    SQL

    execute <<~SQL
      CREATE TRIGGER results_populate_user_id
      BEFORE INSERT OR UPDATE OF search_id ON public.results
      FOR EACH ROW
      EXECUTE FUNCTION public.populate_results_user_id();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS results_populate_user_id ON public.results"
    execute "DROP FUNCTION IF EXISTS public.populate_results_user_id()"
    remove_column :results, :user_id
  end
end
