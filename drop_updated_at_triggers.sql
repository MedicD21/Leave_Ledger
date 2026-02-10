-- Migration: Remove auto-updating updated_at triggers
-- These triggers interfere with client-side timestamp management during sync

-- Drop the triggers that auto-update updated_at
DROP TRIGGER IF EXISTS trigger_leave_entries_updated ON leave_entries;
DROP TRIGGER IF EXISTS trigger_profiles_updated ON profiles;
DROP TRIGGER IF EXISTS trigger_date_notes_updated ON date_notes;

-- Optionally, drop the function if no longer needed
-- (Only drop if no other tables use it)
DROP FUNCTION IF EXISTS update_updated_at();
