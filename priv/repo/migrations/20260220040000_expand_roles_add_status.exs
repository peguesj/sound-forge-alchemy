defmodule SoundForge.Repo.Migrations.ExpandRolesAddStatus do
  use Ecto.Migration

  def up do
    # Drop the old role constraint and recreate with expanded values
    execute "ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check"

    execute """
    ALTER TABLE users ADD CONSTRAINT users_role_check
    CHECK (role IN ('user', 'pro', 'enterprise', 'admin', 'super_admin'))
    """

    # Add status field with default 'active'
    execute """
    ALTER TABLE users ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'active' NOT NULL
    """

    execute """
    ALTER TABLE users ADD CONSTRAINT users_status_check
    CHECK (status IN ('active', 'suspended', 'banned'))
    """

    # Index on role and status for admin queries
    create index(:users, [:role, :status])
  end

  def down do
    drop_if_exists index(:users, [:role, :status])

    execute "ALTER TABLE users DROP CONSTRAINT IF EXISTS users_status_check"
    execute "ALTER TABLE users DROP COLUMN IF EXISTS status"

    execute "ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check"

    execute """
    ALTER TABLE users ADD CONSTRAINT users_role_check
    CHECK (role IN ('user', 'admin'))
    """
  end
end
