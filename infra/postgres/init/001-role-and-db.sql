-- Initialization script for News Postgres
-- Creates role and database if they do not already exist.

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'news') THEN
        CREATE ROLE news WITH LOGIN PASSWORD 'news' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
    END IF;
END
$$;

-- Create database if missing and set owner
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'news') THEN
        CREATE DATABASE news OWNER news;
    END IF;
END
$$;

-- Future placeholder: create schemas/tables here.
-- Example:
-- CREATE SCHEMA IF NOT EXISTS pontoon AUTHORIZATION game;

-- Example dev table (simplistic schema)
CREATE TABLE IF NOT EXISTS prizes (
    id UUID PRIMARY KEY,
    player_id TEXT NOT NULL,
    prize_type TEXT NOT NULL,
    value INT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Grant minimal privileges to game role
GRANT CONNECT ON DATABASE news TO news;
GRANT USAGE ON SCHEMA public TO news;
GRANT SELECT, INSERT ON TABLE prizes TO news;
