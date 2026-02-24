# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

alias SoundForge.Repo
alias SoundForge.Accounts.User
alias SoundForge.Accounts.UserSettings

# System activation key for demo lalal.ai access
system_lalalai_key = System.get_env("SYSTEM_LALALAI_ACTIVATION_KEY")

lalalai_roles = [:pro, :enterprise, :admin, :super_admin]

seed_users = [
  %{email: "dev@soundforge.local", password: "password123456", role: :admin},
  %{email: "demo-free@soundforge.local", password: "demo123456!!", role: :user},
  %{email: "demo-pro@soundforge.local", password: "demo123456!!", role: :pro},
  %{email: "demo-enterprise@soundforge.local", password: "demo123456!!", role: :enterprise},
  %{email: "admin@soundforge.local", password: "admin123456!!", role: :admin},
  %{email: "super@soundforge.local", password: "super123456!!", role: :super_admin}
]

for attrs <- seed_users do
  unless Repo.get_by(User, email: attrs.email) do
    {:ok, user} =
      %User{}
      |> Ecto.Changeset.change(%{
        email: attrs.email,
        hashed_password: Bcrypt.hash_pwd_salt(attrs.password),
        confirmed_at: DateTime.utc_now(:second),
        role: attrs.role
      })
      |> Repo.insert()

    # Build settings attrs, granting lalal.ai access to pro+ roles via system key
    settings_attrs =
      if system_lalalai_key && attrs.role in lalalai_roles do
        %{user_id: user.id, lalalai_api_key: system_lalalai_key}
      else
        %{user_id: user.id}
      end

    %UserSettings{}
    |> UserSettings.changeset(settings_attrs)
    |> Ecto.Changeset.put_change(:user_id, user.id)
    |> Repo.insert(on_conflict: :nothing)

    IO.puts("Seeded #{attrs.role} user: #{attrs.email}")
  else
    IO.puts("User already exists: #{attrs.email}")
  end
end
