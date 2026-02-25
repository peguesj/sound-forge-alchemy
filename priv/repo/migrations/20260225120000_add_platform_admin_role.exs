defmodule SoundForge.Repo.Migrations.AddPlatformAdminRole do
  use Ecto.Migration

  def up do
    # Alter the existing Ecto.Enum column to include :platform_admin.
    # PostgreSQL stores Ecto.Enum values as strings (varchar), so we just need
    # to ensure the constraint allows the new value. Ecto.Enum with :string type
    # does not use a PG enum type by default — so the only constraint is the
    # application-level validation. We add a DB-level check constraint update here
    # to keep the constraint in sync.
    execute """
    ALTER TABLE users
      DROP CONSTRAINT IF EXISTS users_role_check
    """

    execute """
    ALTER TABLE users
      ADD CONSTRAINT users_role_check
      CHECK (role IN ('user','pro','enterprise','admin','super_admin','platform_admin'))
    """
  end

  def down do
    execute """
    ALTER TABLE users
      DROP CONSTRAINT IF EXISTS users_role_check
    """

    execute """
    ALTER TABLE users
      ADD CONSTRAINT users_role_check
      CHECK (role IN ('user','pro','enterprise','admin','super_admin'))
    """
  end
end
