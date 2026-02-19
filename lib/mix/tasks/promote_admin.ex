defmodule Mix.Tasks.PromoteAdmin do
  @moduledoc """
  Promotes a user to admin by email.

  Usage: mix promote_admin user@example.com
  """
  use Mix.Task

  @shortdoc "Promotes a user to admin role"

  @impl true
  def run([email]) do
    Mix.Task.run("app.start")

    alias SoundForge.Repo
    alias SoundForge.Accounts.User
    import Ecto.Query

    case Repo.one(from(u in User, where: u.email == ^email)) do
      nil ->
        Mix.shell().error("No user found with email: #{email}")

      %User{role: :admin} ->
        Mix.shell().info("User #{email} is already an admin.")

      user ->
        user
        |> Ecto.Changeset.change(role: :admin)
        |> Repo.update!()

        Mix.shell().info("Successfully promoted #{email} to admin.")
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix promote_admin user@example.com")
  end
end
