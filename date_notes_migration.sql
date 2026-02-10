-- Migration: Add date_notes table for custom date notes

-- Create date_notes table
CREATE TABLE IF NOT EXISTS public.date_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    title TEXT NOT NULL,
    note_text TEXT NOT NULL,
    color_hex TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS date_notes_user_id_idx ON public.date_notes(user_id);
CREATE INDEX IF NOT EXISTS date_notes_date_idx ON public.date_notes(date);
CREATE INDEX IF NOT EXISTS date_notes_user_date_idx ON public.date_notes(user_id, date);
CREATE INDEX IF NOT EXISTS date_notes_deleted_at_idx ON public.date_notes(deleted_at);

-- Enable Row Level Security
ALTER TABLE public.date_notes ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own notes" ON public.date_notes;
DROP POLICY IF EXISTS "Users can insert their own notes" ON public.date_notes;
DROP POLICY IF EXISTS "Users can update their own notes" ON public.date_notes;
DROP POLICY IF EXISTS "Users can delete their own notes" ON public.date_notes;

-- Create RLS policies for date_notes table
CREATE POLICY "Users can view their own notes"
  ON public.date_notes
  FOR SELECT
  USING (auth.uid()::text = user_id::text OR user_id::text = current_setting('request.headers', true)::json->>'x-user-id');

CREATE POLICY "Users can insert their own notes"
  ON public.date_notes
  FOR INSERT
  WITH CHECK (auth.uid()::text = user_id::text OR user_id::text = current_setting('request.headers', true)::json->>'x-user-id');

CREATE POLICY "Users can update their own notes"
  ON public.date_notes
  FOR UPDATE
  USING (auth.uid()::text = user_id::text OR user_id::text = current_setting('request.headers', true)::json->>'x-user-id');

CREATE POLICY "Users can delete their own notes"
  ON public.date_notes
  FOR DELETE
  USING (auth.uid()::text = user_id::text OR user_id::text = current_setting('request.headers', true)::json->>'x-user-id');
