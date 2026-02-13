# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

alias SoundForge.Repo
alias SoundForge.Accounts.User

# Create dev user if not exists
email = "dev@soundforge.local"

unless Repo.get_by(User, email: email) do
  %User{}
  |> Ecto.Changeset.change(%{
    email: email,
    hashed_password: Bcrypt.hash_pwd_salt("password123456"),
    confirmed_at: DateTime.utc_now(:second)
  })
  |> Repo.insert!()

  IO.puts("Seeded dev user: #{email} / password123456")
else
  IO.puts("Dev user already exists: #{email}")
end
