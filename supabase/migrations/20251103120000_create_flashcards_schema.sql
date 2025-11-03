-- ========================================
-- Migration: Initial 10xCards Schema
-- ========================================
-- Purpose: Create the core database schema for the 10xCards flashcard application
-- Affected tables: flashcards, generations, generation_error_logs
-- Special considerations:
--   - users table is managed by Supabase Auth (auth.users)
--   - RLS policies ensure users can only access their own data
--   - Trigger on flashcards table auto-updates updated_at timestamp
-- ========================================

-- ========================================
-- Table: generations
-- ========================================
-- Purpose: Track flashcard generation sessions with metadata about AI model usage
-- and generation performance metrics
create table if not exists generations (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  model varchar not null,
  generated_count integer not null,
  accepted_unedited_count integer,
  accepted_edited_count integer,
  source_text_hash varchar not null,
  source_text_length integer not null check (source_text_length between 1000 and 10000),
  generation_duration integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Enable Row Level Security on generations table
alter table generations enable row level security;

-- Index for faster user-based queries
create index if not exists idx_generations_user_id on generations(user_id);

-- ========================================
-- Table: flashcards
-- ========================================
-- Purpose: Store individual flashcards with front/back content and tracking
-- of how they were created (AI-generated, manually edited, or fully manual)
create table if not exists flashcards (
  id bigserial primary key,
  front varchar(200) not null,
  back varchar(500) not null,
  source varchar not null check (source in ('ai-full', 'ai-edited', 'manual')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  generation_id bigint references generations(id) on delete set null,
  user_id uuid not null references auth.users(id) on delete cascade
);

-- Enable Row Level Security on flashcards table
alter table flashcards enable row level security;

-- Index for faster user-based queries
create index if not exists idx_flashcards_user_id on flashcards(user_id);

-- Index for faster generation-based queries
create index if not exists idx_flashcards_generation_id on flashcards(generation_id);

-- ========================================
-- Table: generation_error_logs
-- ========================================
-- Purpose: Log errors that occur during AI flashcard generation for debugging
-- and monitoring purposes
create table if not exists generation_error_logs (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  model varchar not null,
  source_text_hash varchar not null,
  source_text_length integer not null check (source_text_length between 1000 and 10000),
  error_code varchar(100) not null,
  error_message text not null,
  created_at timestamptz not null default now()
);

-- Enable Row Level Security on generation_error_logs table
alter table generation_error_logs enable row level security;

-- Index for faster user-based queries
create index if not exists idx_generation_error_logs_user_id on generation_error_logs(user_id);

-- ========================================
-- Trigger Function: update_updated_at_column
-- ========================================
-- Purpose: Automatically update the updated_at timestamp whenever a row is modified
create or replace function update_updated_at_column()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- ========================================
-- Trigger: flashcards update_updated_at
-- ========================================
-- Purpose: Apply the update_updated_at_column function to flashcards table
-- to maintain accurate modification timestamps
create trigger trigger_flashcards_updated_at
  before update on flashcards
  for each row
  execute function update_updated_at_column();

-- ========================================
-- RLS Policies: flashcards
-- ========================================
-- Purpose: Ensure users can only access flashcards they own
-- Roles: anon (unauthenticated), authenticated (logged-in users)

-- Policy: anon users cannot select flashcards
-- Rationale: Flashcards are private and should only be accessible to authenticated users
create policy "anon users cannot select flashcards"
  on flashcards
  for select
  to anon
  using (false);

-- Policy: authenticated users can select their own flashcards
-- Rationale: Users should have full read access to their own flashcards
create policy "authenticated users can select own flashcards"
  on flashcards
  for select
  to authenticated
  using (auth.uid() = user_id);

-- Policy: anon users cannot insert flashcards
-- Rationale: Only authenticated users should be able to create flashcards
create policy "anon users cannot insert flashcards"
  on flashcards
  for insert
  to anon
  with check (false);

-- Policy: authenticated users can insert their own flashcards
-- Rationale: Users should be able to create new flashcards for themselves
create policy "authenticated users can insert own flashcards"
  on flashcards
  for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Policy: anon users cannot update flashcards
-- Rationale: Only authenticated users should be able to modify flashcards
create policy "anon users cannot update flashcards"
  on flashcards
  for update
  to anon
  using (false);

-- Policy: authenticated users can update their own flashcards
-- Rationale: Users should be able to edit their own flashcards
create policy "authenticated users can update own flashcards"
  on flashcards
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Policy: anon users cannot delete flashcards
-- Rationale: Only authenticated users should be able to delete flashcards
create policy "anon users cannot delete flashcards"
  on flashcards
  for delete
  to anon
  using (false);

-- Policy: authenticated users can delete their own flashcards
-- Rationale: Users should be able to remove their own flashcards
create policy "authenticated users can delete own flashcards"
  on flashcards
  for delete
  to authenticated
  using (auth.uid() = user_id);

-- ========================================
-- RLS Policies: generations
-- ========================================
-- Purpose: Ensure users can only access generation records they own
-- Roles: anon (unauthenticated), authenticated (logged-in users)

-- Policy: anon users cannot select generations
-- Rationale: Generation records are private and should only be accessible to authenticated users
create policy "anon users cannot select generations"
  on generations
  for select
  to anon
  using (false);

-- Policy: authenticated users can select their own generations
-- Rationale: Users should have full read access to their own generation history
create policy "authenticated users can select own generations"
  on generations
  for select
  to authenticated
  using (auth.uid() = user_id);

-- Policy: anon users cannot insert generations
-- Rationale: Only authenticated users should be able to create generation records
create policy "anon users cannot insert generations"
  on generations
  for insert
  to anon
  with check (false);

-- Policy: authenticated users can insert their own generations
-- Rationale: Users should be able to create new generation records for themselves
create policy "authenticated users can insert own generations"
  on generations
  for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Policy: anon users cannot update generations
-- Rationale: Only authenticated users should be able to modify generation records
create policy "anon users cannot update generations"
  on generations
  for update
  to anon
  using (false);

-- Policy: authenticated users can update their own generations
-- Rationale: Users should be able to update their generation records (e.g., accepted counts)
create policy "authenticated users can update own generations"
  on generations
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Policy: anon users cannot delete generations
-- Rationale: Only authenticated users should be able to delete generation records
create policy "anon users cannot delete generations"
  on generations
  for delete
  to anon
  using (false);

-- Policy: authenticated users can delete their own generations
-- Rationale: Users should be able to remove their own generation records
create policy "authenticated users can delete own generations"
  on generations
  for delete
  to authenticated
  using (auth.uid() = user_id);

-- ========================================
-- RLS Policies: generation_error_logs
-- ========================================
-- Purpose: Ensure users can only access error logs they own
-- Roles: anon (unauthenticated), authenticated (logged-in users)

-- Policy: anon users cannot select generation error logs
-- Rationale: Error logs are private and should only be accessible to authenticated users
create policy "anon users cannot select generation_error_logs"
  on generation_error_logs
  for select
  to anon
  using (false);

-- Policy: authenticated users can select their own generation error logs
-- Rationale: Users should have access to error logs for their own generation attempts
create policy "authenticated users can select own generation_error_logs"
  on generation_error_logs
  for select
  to authenticated
  using (auth.uid() = user_id);

-- Policy: anon users cannot insert generation error logs
-- Rationale: Only authenticated users should be able to create error log records
create policy "anon users cannot insert generation_error_logs"
  on generation_error_logs
  for insert
  to anon
  with check (false);

-- Policy: authenticated users can insert their own generation error logs
-- Rationale: Users should be able to log errors for their own generation attempts
create policy "authenticated users can insert own generation_error_logs"
  on generation_error_logs
  for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Policy: anon users cannot update generation error logs
-- Rationale: Error logs should be immutable, but only authenticated users could update if needed
create policy "anon users cannot update generation_error_logs"
  on generation_error_logs
  for update
  to anon
  using (false);

-- Policy: authenticated users can update their own generation error logs
-- Rationale: Users might need to update error log records, though typically these are immutable
create policy "authenticated users can update own generation_error_logs"
  on generation_error_logs
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Policy: anon users cannot delete generation error logs
-- Rationale: Only authenticated users should be able to delete error logs
create policy "anon users cannot delete generation_error_logs"
  on generation_error_logs
  for delete
  to anon
  using (false);

-- Policy: authenticated users can delete their own generation error logs
-- Rationale: Users should be able to remove their own error log records
create policy "authenticated users can delete own generation_error_logs"
  on generation_error_logs
  for delete
  to authenticated

