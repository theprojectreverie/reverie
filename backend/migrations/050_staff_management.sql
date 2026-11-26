CREATE TABLE IF NOT EXISTS reverie_staff_roles (
 account_id uuid PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
 role text NOT NULL CHECK(role IN ('admin','moderator','analyst')),
 assigned_by uuid NOT NULL,
 assigned_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS reverie_staff_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 actor_account_id uuid NOT NULL,
 target_account_id uuid NOT NULL,
 target_name text NOT NULL,
 previous_role text,
 new_role text,
 note text NOT NULL CHECK(length(note) BETWEEN 8 AND 300),
 created_at timestamptz NOT NULL DEFAULT now()
);