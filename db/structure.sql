SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: current_user_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_user_id() RETURNS bigint
    LANGUAGE sql STABLE
    AS $$
  SELECT NULLIF(current_setting('app.current_user_id', true), '')::bigint;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id bigint NOT NULL,
    name character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint
);


--
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.categories_id_seq OWNED BY public.categories.id;


--
-- Name: prompts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prompts (
    id bigint NOT NULL,
    search_id bigint NOT NULL,
    target_id bigint,
    full_query_text character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying,
    error_message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.prompts FORCE ROW LEVEL SECURITY;


--
-- Name: prompts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.prompts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: prompts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.prompts_id_seq OWNED BY public.prompts.id;


--
-- Name: results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.results (
    id bigint NOT NULL,
    search_id bigint NOT NULL,
    url character varying NOT NULL,
    url_hash character varying NOT NULL,
    title character varying,
    content text,
    viewed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status character varying DEFAULT 'unread'::character varying NOT NULL,
    acknowledged boolean DEFAULT false NOT NULL
);

ALTER TABLE ONLY public.results FORCE ROW LEVEL SECURITY;


--
-- Name: results_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.results_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: results_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.results_id_seq OWNED BY public.results.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: searches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.searches (
    id bigint NOT NULL,
    title character varying,
    query_conditions text,
    status character varying DEFAULT 'pending'::character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    time_frame character varying,
    show_acknowledged boolean DEFAULT false NOT NULL,
    user_id bigint
);

ALTER TABLE ONLY public.searches FORCE ROW LEVEL SECURITY;


--
-- Name: searches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.searches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: searches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.searches_id_seq OWNED BY public.searches.id;


--
-- Name: targets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.targets (
    id bigint NOT NULL,
    category_id bigint NOT NULL,
    name character varying,
    domain character varying,
    is_active boolean DEFAULT true,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    allow_query_strings boolean DEFAULT false NOT NULL
);


--
-- Name: targets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.targets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: targets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.targets_id_seq OWNED BY public.targets.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp(6) without time zone,
    remember_created_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: categories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories ALTER COLUMN id SET DEFAULT nextval('public.categories_id_seq'::regclass);


--
-- Name: prompts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompts ALTER COLUMN id SET DEFAULT nextval('public.prompts_id_seq'::regclass);


--
-- Name: results id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.results ALTER COLUMN id SET DEFAULT nextval('public.results_id_seq'::regclass);


--
-- Name: searches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.searches ALTER COLUMN id SET DEFAULT nextval('public.searches_id_seq'::regclass);


--
-- Name: targets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.targets ALTER COLUMN id SET DEFAULT nextval('public.targets_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: prompts prompts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompts
    ADD CONSTRAINT prompts_pkey PRIMARY KEY (id);


--
-- Name: results results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.results
    ADD CONSTRAINT results_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: searches searches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.searches
    ADD CONSTRAINT searches_pkey PRIMARY KEY (id);


--
-- Name: targets targets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.targets
    ADD CONSTRAINT targets_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_results_analytics; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_results_analytics ON public.results USING btree (search_id, status, acknowledged);


--
-- Name: idx_results_content_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_results_content_trgm ON public.results USING gin (content public.gin_trgm_ops);


--
-- Name: idx_results_title_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_results_title_trgm ON public.results USING gin (title public.gin_trgm_ops);


--
-- Name: idx_results_url_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_results_url_trgm ON public.results USING gin (url public.gin_trgm_ops);


--
-- Name: index_categories_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_categories_on_user_id ON public.categories USING btree (user_id);


--
-- Name: index_categories_on_user_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_categories_on_user_id_and_name ON public.categories USING btree (user_id, name);


--
-- Name: index_global_prompts_on_search_and_query; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_global_prompts_on_search_and_query ON public.prompts USING btree (search_id, full_query_text) WHERE (target_id IS NULL);


--
-- Name: index_prompts_on_search_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_prompts_on_search_id ON public.prompts USING btree (search_id);


--
-- Name: index_prompts_on_search_target_and_query; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_prompts_on_search_target_and_query ON public.prompts USING btree (search_id, target_id, full_query_text) WHERE (target_id IS NOT NULL);


--
-- Name: index_prompts_on_target_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_prompts_on_target_id ON public.prompts USING btree (target_id);


--
-- Name: index_results_on_search_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_results_on_search_id ON public.results USING btree (search_id);


--
-- Name: index_results_on_search_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_results_on_search_id_and_status ON public.results USING btree (search_id, status);


--
-- Name: index_results_on_search_id_and_url_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_results_on_search_id_and_url_hash ON public.results USING btree (search_id, url_hash);


--
-- Name: index_results_on_url_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_results_on_url_hash ON public.results USING btree (url_hash);


--
-- Name: index_searches_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_searches_on_user_id ON public.searches USING btree (user_id);


--
-- Name: index_targets_on_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_targets_on_category_id ON public.targets USING btree (category_id);


--
-- Name: index_targets_on_domain; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_targets_on_domain ON public.targets USING btree (domain);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: prompts fk_rails_215a3800e7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompts
    ADD CONSTRAINT fk_rails_215a3800e7 FOREIGN KEY (search_id) REFERENCES public.searches(id);


--
-- Name: prompts fk_rails_34be8e4a7d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompts
    ADD CONSTRAINT fk_rails_34be8e4a7d FOREIGN KEY (target_id) REFERENCES public.targets(id);


--
-- Name: targets fk_rails_7eab9384bf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.targets
    ADD CONSTRAINT fk_rails_7eab9384bf FOREIGN KEY (category_id) REFERENCES public.categories(id);


--
-- Name: results fk_rails_805f7d6ac0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.results
    ADD CONSTRAINT fk_rails_805f7d6ac0 FOREIGN KEY (search_id) REFERENCES public.searches(id);


--
-- Name: categories fk_rails_b8e2f7adfc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT fk_rails_b8e2f7adfc FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: searches fk_rails_e192b86393; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.searches
    ADD CONSTRAINT fk_rails_e192b86393 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: prompts prompt_user_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY prompt_user_isolation ON public.prompts USING ((EXISTS ( SELECT 1
   FROM public.searches
  WHERE ((searches.id = prompts.search_id) AND (searches.user_id = public.current_user_id())))));


--
-- Name: prompts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.prompts ENABLE ROW LEVEL SECURITY;

--
-- Name: results result_user_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY result_user_isolation ON public.results USING ((EXISTS ( SELECT 1
   FROM public.searches
  WHERE ((searches.id = results.search_id) AND (searches.user_id = public.current_user_id())))));


--
-- Name: results; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.results ENABLE ROW LEVEL SECURITY;

--
-- Name: searches search_user_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY search_user_isolation ON public.searches USING ((user_id = public.current_user_id())) WITH CHECK ((user_id = public.current_user_id()));


--
-- Name: searches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.searches ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260813112403'),
('20260731104737'),
('20260731091405'),
('20260731091333'),
('20260705090113'),
('20260702082718'),
('20260701182844'),
('20260628101130'),
('20260628074455'),
('20260626183215'),
('20260626092937'),
('20260625095216'),
('20260615112243'),
('20260611122715'),
('20260611122633'),
('20260611122611'),
('20260611122552'),
('20260611122511');

