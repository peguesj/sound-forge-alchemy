defmodule SoundForge.Admin do
  @moduledoc """
  Admin context for cross-user queries and system management.
  """

  import Ecto.Query
  alias SoundForge.Repo
  alias SoundForge.Accounts.User
  alias SoundForge.Music.Track

  def list_users(opts \\ []) do
    sort = Keyword.get(opts, :sort, :inserted_at)
    dir = Keyword.get(opts, :dir, :desc)

    from(u in User,
      left_join: t in Track, on: t.user_id == u.id,
      group_by: u.id,
      select: %{
        id: u.id,
        email: u.email,
        role: u.role,
        track_count: count(t.id),
        confirmed_at: u.confirmed_at,
        inserted_at: u.inserted_at
      },
      order_by: [{^dir, ^sort}]
    )
    |> Repo.all()
  end

  def update_user_role(user_id, role) when role in [:user, :admin] do
    Repo.get!(User, user_id)
    |> Ecto.Changeset.change(role: role)
    |> Repo.update()
  end

  def system_stats do
    user_count = Repo.aggregate(User, :count)
    track_count = Repo.aggregate(Track, :count)

    oban_stats = oban_job_stats()

    %{
      user_count: user_count,
      track_count: track_count,
      oban: oban_stats
    }
  end

  def all_jobs(opts \\ []) do
    state = Keyword.get(opts, :state, "all")

    query =
      from(j in "oban_jobs",
        select: %{
          id: j.id,
          queue: j.queue,
          worker: j.worker,
          state: j.state,
          args: j.args,
          inserted_at: j.inserted_at,
          attempted_at: j.attempted_at,
          errors: j.errors
        },
        order_by: [desc: j.inserted_at],
        limit: 100
      )

    query =
      if state != "all" do
        from(j in query, where: j.state == ^state)
      else
        query
      end

    Repo.all(query)
  end

  def storage_stats do
    storage_dir = Application.get_env(:sound_forge, :storage_dir, "priv/storage")

    case System.cmd("du", ["-sh", storage_dir], stderr_to_stdout: true) do
      {output, 0} ->
        [size | _] = String.split(output, "\t")
        %{total_size: String.trim(size), path: storage_dir}

      _ ->
        %{total_size: "unknown", path: storage_dir}
    end
  end

  defp oban_job_stats do
    query =
      from(j in "oban_jobs",
        group_by: j.state,
        select: {j.state, count(j.id)}
      )

    Repo.all(query) |> Map.new()
  end
end
