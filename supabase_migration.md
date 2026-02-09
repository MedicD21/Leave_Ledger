# Supabase Database Migration for Leave Ledger

This migration script will:
- Remove unused tables (`user_profiles`, `sync_meta`)
- Update the `profiles` table with authentication and configuration fields
- Ensure `leave_entries` table is properly configured
- Set up Row Level Security (RLS) policies
- Create necessary indexes for performance

**Run this in your Supabase SQL Editor:**

---

## Step 1: Drop Unused Tables

```sql
-- Drop unused tables
DROP TABLE IF EXISTS public.user_profiles CASCADE;
DROP TABLE IF EXISTS public.sync_meta CASCADE;
```

---

## Step 2: Update Profiles Table

```sql
-- Add new columns to profiles table
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS apple_user_id TEXT,
ADD COLUMN IF NOT EXISTS email TEXT,
ADD COLUMN IF NOT EXISTS is_authenticated BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS is_setup_complete BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS pay_period_type TEXT DEFAULT 'biweekly',
ADD COLUMN IF NOT EXISTS pay_period_interval INTEGER DEFAULT 14,
ADD COLUMN IF NOT EXISTS comp_enabled BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS vacation_enabled BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS sick_enabled BOOLEAN DEFAULT true;

-- Add index on apple_user_id for faster lookups
CREATE INDEX IF NOT EXISTS profiles_apple_user_id_idx ON public.profiles(apple_user_id);

-- Add index on email for faster lookups
CREATE INDEX IF NOT EXISTS profiles_email_idx ON public.profiles(email);
```

---

## Step 3: Verify Leave Entries Table

```sql
-- Ensure leave_entries table has correct structure
-- (This should already exist, but we'll verify the indexes)

-- Add index on user_id for faster queries
CREATE INDEX IF NOT EXISTS leave_entries_user_id_idx ON public.leave_entries(user_id);

-- Add index on date for faster date-based queries
CREATE INDEX IF NOT EXISTS leave_entries_date_idx ON public.leave_entries(date);

-- Add composite index for user + date queries (most common query pattern)
CREATE INDEX IF NOT EXISTS leave_entries_user_date_idx ON public.leave_entries(user_id, date);

-- Add index on deleted_at for filtering non-deleted entries
CREATE INDEX IF NOT EXISTS leave_entries_deleted_at_idx ON public.leave_entries(deleted_at);
```

---

## Step 4: Set Up Row Level Security (RLS)

```sql
-- Enable RLS on profiles table
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Enable RLS on leave_entries table
ALTER TABLE public.leave_entries ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can view their own entries" ON public.leave_entries;
DROP POLICY IF EXISTS "Users can insert their own entries" ON public.leave_entries;
DROP POLICY IF EXISTS "Users can update their own entries" ON public.leave_entries;
DROP POLICY IF EXISTS "Users can delete their own entries" ON public.leave_entries;

-- Create RLS policies for profiles table
CREATE POLICY "Users can view their own profile"
  ON public.profiles
  FOR SELECT
  USING (auth.uid()::text = id::text OR id::text = current_setting('request.headers', true)::json->>'x-user-id');

CREATE POLICY "Users can update their own profile"
  ON public.profiles
  FOR UPDATE
  USING (auth.uid()::text = id::text OR id::text = current_setting('request.headers', true)::json->>'x-user-id');

CREATE POLICY "Users can insert their own profile"
  ON public.profiles
  FOR INSERT
  WITH CHECK (auth.uid()::text = id::text OR id::text = current_setting('request.headers', true)::json->>'x-user-id');

-- Create RLS policies for leave_entries table
CREATE POLICY "Users can view their own entries"
  ON public.leave_entries
  FOR SELECT
  USING (auth.uid()::text = user_id::text OR user_id::text = current_setting('request.headers', true)::json->>'x-user-id');

CREATE POLICY "Users can insert their own entries"
  ON public.leave_entries
  FOR INSERT
  WITH CHECK (auth.uid()::text = user_id::text OR user_id::text = current_setting('request.headers', true)::json->>'x-user-id');

CREATE POLICY "Users can update their own entries"
  ON public.leave_entries
  FOR UPDATE
  USING (auth.uid()::text = user_id::text OR user_id::text = current_setting('request.headers', true)::json->>'x-user-id');

CREATE POLICY "Users can delete their own entries"
  ON public.leave_entries
  FOR DELETE
  USING (auth.uid()::text = user_id::text OR user_id::text = current_setting('request.headers', true)::json->>'x-user-id');
```

---

## Step 5: Verify Schema

```sql
-- Verify profiles table structure
SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'profiles'
ORDER BY ordinal_position;

-- Verify leave_entries table structure
SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'leave_entries'
ORDER BY ordinal_position;
```

---

## Expected Results

After running this migration, you should have:

### `profiles` Table Columns:
- `id` (uuid, primary key)
- `created_at` (timestamp with time zone)
- `updated_at` (timestamp with time zone)
- `anchor_payday` (date)
- `sick_start_balance` (numeric)
- `vac_start_balance` (numeric)
- `comp_start_balance` (numeric)
- `sick_accrual_rate` (numeric)
- `vac_accrual_rate` (numeric)
- `ical_token` (text)
- `settings` (jsonb)
- **`apple_user_id`** (text) ← NEW
- **`email`** (text) ← NEW
- **`is_authenticated`** (boolean) ← NEW
- **`is_setup_complete`** (boolean) ← NEW
- **`pay_period_type`** (text) ← NEW
- **`pay_period_interval`** (integer) ← NEW
- **`comp_enabled`** (boolean) ← NEW
- **`vacation_enabled`** (boolean) ← NEW
- **`sick_enabled`** (boolean) ← NEW

### `leave_entries` Table Columns:
- `id` (uuid, primary key)
- `user_id` (uuid, foreign key to profiles.id)
- `date` (date)
- `leave_type` (user-defined enum)
- `action` (user-defined enum)
- `hours` (numeric)
- `adjustment_sign` (user-defined enum)
- `notes` (text)
- `source` (user-defined enum)
- `created_at` (timestamp with time zone)
- `updated_at` (timestamp with time zone)
- `deleted_at` (timestamp with time zone)

---

## Notes

- **RLS Policies**: Support both authenticated users (via `auth.uid()`) and device-based access (via `x-user-id` header) for backward compatibility
- **Indexes**: Added for optimal query performance on common access patterns
- **Unused Tables**: `user_profiles` and `sync_meta` tables are removed as they're not used by the app
- **Apple Sign In**: You still need to enable the Apple provider in Supabase Authentication settings

---

## Post-Migration Checklist

- [ ] Run migration SQL in Supabase SQL Editor
- [ ] Verify schema with the verification queries at the end
- [ ] Enable Apple Sign In provider in Supabase Dashboard → Authentication → Providers
- [ ] Delete the Leave Ledger app from your test device/simulator
- [ ] Rebuild and run the app to test with fresh database
