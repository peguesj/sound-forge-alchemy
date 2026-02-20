defmodule SoundForge.Admin do
  @moduledoc """
  Admin context for cross-user queries, system management,
  analytics, and audit logging.
  """

  import Ecto.Query
  alias SoundForge.Repo
  alias SoundForge.Accounts.User
  alias SoundForge.Music.Track
  alias SoundForge.Admin.AuditLog

  @valid_roles ~w(user pro enterprise admin super_admin)a

  # ============================================================
  # User Management
  # ============================================================

  @doc """
  Returns a paginated list of users with optional search, role, and status filters.

  Accepts keyword options: `:sort`, `:dir`, `:page`, `:per_page`, `:search`, `:role`, `:status`.
  Returns `%{users: list, total: integer, page: integer, per_page: integer}`.
  """
  def list_users(opts \\ []) do
    sort = Keyword.get(opts, :sort, :inserted_at)
    dir = Keyword.get(opts, :dir, :desc)
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 25)
    search = Keyword.get(opts, :search)
    role_filter = Keyword.get(opts, :role)
    status_filter = Keyword.get(opts, :status)

    offset = (page - 1) * per_page

    query =
      from(u in User,
        left_join: t in Track, on: t.user_id == u.id,
        group_by: u.id,
        select: %{
          id: u.id,
          email: u.email,
          role: u.role,
          status: u.status,
          track_count: count(t.id),
          confirmed_at: u.confirmed_at,
          inserted_at: u.inserted_at
        },
        order_by: [{^dir, ^sort}],
        offset: ^offset,
        limit: ^per_page
      )

    query = if search, do: from(u in query, where: ilike(u.email, ^"%#{search}%")), else: query
    query = if role_filter, do: from(u in query, where: u.role == ^role_filter), else: query
    query = if status_filter, do: from(u in query, where: u.status == ^status_filter), else: query

    users = Repo.all(query)

    total =
      from(u in User)
      |> maybe_filter_search(search)
      |> maybe_filter_role(role_filter)
      |> maybe_filter_status(status_filter)
      |> Repo.aggregate(:count)

    %{users: users, total: total, page: page, per_page: per_page}
  end

  defp maybe_filter_search(query, nil), do: query
  defp maybe_filter_search(query, search), do: from(u in query, where: ilike(u.email, ^"%#{search}%"))

  defp maybe_filter_role(query, nil), do: query
  defp maybe_filter_role(query, role), do: from(u in query, where: u.role == ^role)

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: from(u in query, where: u.status == ^status)

  @doc "Updates a user's role and logs the change to the audit trail."
  def update_user_role(user_id, role, actor_id \\ nil) when role in @valid_roles do
    user = Repo.get!(User, user_id)
    old_role = user.role

    result =
      user
      |> Ecto.Changeset.change(role: role)
      |> Repo.update()

    case result do
      {:ok, updated_user} ->
        log_action(actor_id, "role_change", "user", to_string(user_id), %{
          from: to_string(old_role),
          to: to_string(role)
        })

        {:ok, updated_user}

      error ->
        error
    end
  end

  @doc "Sets a user's status to `:suspended`. Audit-logged."
  def suspend_user(user_id, actor_id \\ nil) do
    update_user_status(user_id, :suspended, "suspend", actor_id)
  end

  @doc "Sets a user's status to `:banned`. Audit-logged."
  def ban_user(user_id, actor_id \\ nil) do
    update_user_status(user_id, :banned, "ban", actor_id)
  end

  @doc "Restores a suspended or banned user to `:active` status. Audit-logged."
  def reactivate_user(user_id, actor_id \\ nil) do
    update_user_status(user_id, :active, "reactivate", actor_id)
  end

  defp update_user_status(user_id, new_status, action, actor_id) do
    user = Repo.get!(User, user_id)
    old_status = user.status

    result =
      user
      |> Ecto.Changeset.change(status: new_status)
      |> Repo.update()

    case result do
      {:ok, updated_user} ->
        log_action(actor_id, action, "user", to_string(user_id), %{
          from: to_string(old_status),
          to: to_string(new_status)
        })

        {:ok, updated_user}

      error ->
        error
    end
  end

  @doc "Updates the role for multiple users in a single query. Audit-logged with the full list of affected user IDs."
  def bulk_update_role(user_ids, role, actor_id \\ nil) when role in @valid_roles do
    {count, _} =
      from(u in User, where: u.id in ^user_ids)
      |> Repo.update_all(set: [role: role])

    log_action(actor_id, "bulk_role_change", "user", "bulk:#{length(user_ids)}", %{
      user_ids: Enum.map(user_ids, &to_string/1),
      to: to_string(role),
      count: count
    })

    {:ok, count}
  end

  # ============================================================
  # System Stats & Jobs
  # ============================================================

  @doc "Returns aggregate system statistics: user/track counts, Oban job states, and breakdowns by role and status."
  def system_stats do
    user_count = Repo.aggregate(User, :count)
    track_count = Repo.aggregate(Track, :count)
    oban_stats = oban_job_stats()

    users_by_role =
      from(u in User, group_by: u.role, select: {u.role, count(u.id)})
      |> Repo.all()
      |> Map.new()

    users_by_status =
      from(u in User, group_by: u.status, select: {u.status, count(u.id)})
      |> Repo.all()
      |> Map.new()

    %{
      user_count: user_count,
      track_count: track_count,
      oban: oban_stats,
      users_by_role: users_by_role,
      users_by_status: users_by_status
    }
  end

  @doc "Returns a paginated list of Oban jobs, optionally filtered by state."
  def all_jobs(opts \\ []) do
    state = Keyword.get(opts, :state, "all")
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)
    offset = (page - 1) * per_page

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
        offset: ^offset,
        limit: ^per_page
      )

    query =
      if state != "all" do
        from(j in query, where: j.state == ^state)
      else
        query
      end

    Repo.all(query)
  end

  @doc "Returns disk usage statistics for the configured storage directory."
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

  # ============================================================
  # Analytics
  # ============================================================

  @doc "Returns daily user registration counts for the last `days` days (default 30)."
  def user_registrations_by_day(days \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86400, :second)

    from(u in User,
      where: u.inserted_at >= ^cutoff,
      group_by: fragment("DATE(?)", u.inserted_at),
      select: %{
        date: fragment("DATE(?)", u.inserted_at),
        count: count(u.id)
      },
      order_by: [asc: fragment("DATE(?)", u.inserted_at)]
    )
    |> Repo.all()
  end

  @doc "Returns daily track import counts for the last `days` days (default 30)."
  def tracks_by_day(days \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86400, :second)

    from(t in Track,
      where: t.inserted_at >= ^cutoff,
      group_by: fragment("DATE(?)", t.inserted_at),
      select: %{
        date: fragment("DATE(?)", t.inserted_at),
        count: count(t.id)
      },
      order_by: [asc: fragment("DATE(?)", t.inserted_at)]
    )
    |> Repo.all()
  end

  @doc "Returns Oban job counts grouped by queue (download/processing/analysis) and state."
  def pipeline_throughput do
    query =
      from(j in "oban_jobs",
        where: j.queue in ~w(download processing analysis),
        group_by: [j.queue, j.state],
        select: {j.queue, j.state, count(j.id)}
      )

    Repo.all(query)
    |> Enum.group_by(&elem(&1, 0), fn {_q, state, count} -> {state, count} end)
    |> Map.new(fn {queue, stats} -> {queue, Map.new(stats)} end)
  end

  # ============================================================
  # Audit Logging
  # ============================================================

  @doc "Inserts an audit log entry recording an admin action against a resource."
  def log_action(actor_id, action, resource_type, resource_id, changes \\ %{}, ip \\ nil) do
    %AuditLog{}
    |> AuditLog.changeset(%{
      actor_id: actor_id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      changes: changes,
      ip_address: ip
    })
    |> Repo.insert()
  end

  @doc "Returns a paginated list of audit log entries with optional action, resource type, and search filters."
  def list_audit_logs(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)
    action_filter = Keyword.get(opts, :action)
    resource_filter = Keyword.get(opts, :resource_type)
    search = Keyword.get(opts, :search)
    offset = (page - 1) * per_page

    query =
      from(a in AuditLog,
        left_join: u in User, on: u.id == a.actor_id,
        select: %{
          id: a.id,
          action: a.action,
          resource_type: a.resource_type,
          resource_id: a.resource_id,
          changes: a.changes,
          ip_address: a.ip_address,
          inserted_at: a.inserted_at,
          actor_email: u.email
        },
        order_by: [desc: a.inserted_at],
        offset: ^offset,
        limit: ^per_page
      )

    query = if action_filter, do: from(a in query, where: a.action == ^action_filter), else: query
    query = if resource_filter, do: from(a in query, where: a.resource_type == ^resource_filter), else: query

    query =
      if search do
        from(a in query,
          where:
            ilike(a.resource_id, ^"%#{search}%") or
              ilike(a.action, ^"%#{search}%")
        )
      else
        query
      end

    Repo.all(query)
  end
end
