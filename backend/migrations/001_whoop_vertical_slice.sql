create table if not exists app_installations (
  id uuid primary key,
  session_generation integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists oauth_transactions (
  state_hash text primary key,
  installation_id uuid not null references app_installations(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists oauth_exchange_codes (
  code_hash text primary key,
  installation_id uuid not null references app_installations(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists whoop_credentials (
  installation_id uuid primary key references app_installations(id) on delete cascade,
  whoop_user_id text not null,
  encrypted_access_token text not null,
  encrypted_refresh_token text not null,
  access_expires_at timestamptz not null,
  scope text not null,
  token_version integer not null default 1,
  updated_at timestamptz not null default now()
);

create table if not exists sync_checkpoints (
  installation_id uuid not null references app_installations(id) on delete cascade,
  resource_type text not null check (resource_type in ('cycle', 'recovery', 'sleep', 'workout')),
  last_successful_sync_at timestamptz not null,
  last_source_updated_at timestamptz,
  primary key (installation_id, resource_type)
);

create index if not exists oauth_transactions_expires_at_idx
  on oauth_transactions (expires_at);

create index if not exists oauth_exchange_codes_expires_at_idx
  on oauth_exchange_codes (expires_at);
