CREATE USER app_user WITH PASSWORD 'password' NOSUPERUSER CREATEDB;

GRANT ALL PRIVILEGES ON DATABASE brute_force_finder_app_development TO app_user;

\c brute_force_finder_app_development
GRANT ALL ON SCHEMA public TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO app_user;