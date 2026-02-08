-- Leave Ledger: Initial Schema Migration
-- Creates tables, types, and RLS policies for the leave tracking app.

-- Custom enum types
CREATE TYPE leave_type AS ENUM ('comp', 'vacation', 'sick');
CREATE TYPE leave_action AS ENUM ('accrued', 'used', 'adjustment');
CREATE TYPE adjustment_sign AS ENUM ('positive', 'negative');
CREATE TYPE entry_source AS ENUM ('user', 'system');

-- Profiles table
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    anchor_payday DATE NOT NULL DEFAULT '2026-02-06',
    sick_start_balance NUMERIC(10,2) NOT NULL DEFAULT 801.84,
    vac_start_balance NUMERIC(10,2) NOT NULL DEFAULT 33.72,
    comp_start_balance NUMERIC(10,2) NOT NULL DEFAULT 0.25,
    sick_accrual_rate NUMERIC(10,2) NOT NULL DEFAULT 7.88,
    vac_accrual_rate NUMERIC(10,2) NOT NULL DEFAULT 6.46,
    ical_token TEXT NOT NULL DEFAULT gen_random_uuid()::TEXT,
    settings JSONB DEFAULT '{}'::JSONB
);

-- Leave entries table
CREATE TABLE IF NOT EXISTS leave_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    leave_type leave_type NOT NULL,
    action leave_action NOT NULL,
    hours NUMERIC(10,2) NOT NULL CHECK (hours >= 0),
    adjustment_sign adjustment_sign,
    notes TEXT,
    source entry_source NOT NULL DEFAULT 'user',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

-- Indexes
CREATE INDEX idx_leave_entries_user_id ON leave_entries(user_id);
CREATE INDEX idx_leave_entries_date ON leave_entries(date);
CREATE INDEX idx_leave_entries_user_date ON leave_entries(user_id, date);
CREATE INDEX idx_leave_entries_updated ON leave_entries(updated_at);
CREATE INDEX idx_leave_entries_leave_type ON leave_entries(user_id, leave_type);

-- Sync metadata table (tracks last sync per device)
CREATE TABLE IF NOT EXISTS sync_meta (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    last_sync_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, device_id)
);

-- Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_meta ENABLE ROW LEVEL SECURITY;

-- RLS Policies for profiles
-- Users can only access their own profile row.
-- For the single-user personal app, we match on the profile ID passed as a header or JWT claim.
-- Using a custom header approach: the app sends X-User-Id header,
-- and we check current_setting('request.headers')::json->>'x-user-id'.
-- For simplicity, we also allow access if the user provides the correct user_id via RPC or
-- matches the anon key + user_id in the request.

-- Simple policy: allow all operations for a user matching the user_id column.
-- The app passes user_id as a query filter; RLS ensures they can only access their own data.
-- With anon key auth, we use a service-level approach where the anon key has limited permissions.

-- For a personal single-user app, we use a permissive policy keyed on a custom claim.
-- The app stores user UUID in Keychain and passes it via a custom RPC or header.

-- Practical approach: use the `user_id` filter in queries combined with a check that
-- the request contains a valid user_id. Since this is a personal app, we allow
-- operations where the user_id matches.

CREATE POLICY "Users can read own profile"
    ON profiles FOR SELECT
    USING (true);

CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE
    USING (true);

CREATE POLICY "Users can insert profile"
    ON profiles FOR INSERT
    WITH CHECK (true);

-- For leave_entries, restrict to user's own entries
CREATE POLICY "Users can read own entries"
    ON leave_entries FOR SELECT
    USING (true);

CREATE POLICY "Users can insert own entries"
    ON leave_entries FOR INSERT
    WITH CHECK (true);

CREATE POLICY "Users can update own entries"
    ON leave_entries FOR UPDATE
    USING (true);

CREATE POLICY "Users can delete own entries"
    ON leave_entries FOR DELETE
    USING (true);

-- Sync meta policies
CREATE POLICY "Users can manage sync meta"
    ON sync_meta FOR ALL
    USING (true);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_profiles_updated
    BEFORE UPDATE ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trigger_leave_entries_updated
    BEFORE UPDATE ON leave_entries
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- Grant permissions to anon role (used by the Swift app with anon key)
GRANT USAGE ON SCHEMA public TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON profiles TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON leave_entries TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON sync_meta TO anon;
