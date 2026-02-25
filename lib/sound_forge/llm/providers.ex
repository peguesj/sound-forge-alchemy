defmodule SoundForge.LLM.Providers do
  @moduledoc """
  Context module for managing LLM provider configurations.

  Provides CRUD operations for persisted provider records, plus convenience
  functions for toggling, reordering, and querying enabled providers.

  For system-level (env-var) provider fallbacks, see
  `SoundForge.LLM.Providers.SystemProviders`.
  """

  import Ecto.Query, warn: false
  alias SoundForge.Repo
  alias SoundForge.LLM.Provider

  # ---------------------------------------------------------------------------
  # Read
  # ---------------------------------------------------------------------------

  @doc """
  Returns all providers for a user, ordered by priority ASC.
  """
  @spec list_providers(term()) :: [Provider.t()]
  def list_providers(user_id) do
    Provider
    |> where([p], p.user_id == ^user_id)
    |> order_by([p], asc: p.priority)
    |> Repo.all()
  end

  @doc """
  Returns only enabled providers for a user, sorted by priority ASC.
  """
  @spec get_enabled_providers(term()) :: [Provider.t()]
  def get_enabled_providers(user_id) do
    Provider
    |> where([p], p.user_id == ^user_id and p.enabled == true)
    |> order_by([p], asc: p.priority)
    |> Repo.all()
  end

  @doc """
  Gets a single provider by ID. Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_provider!(binary()) :: Provider.t()
  def get_provider!(id) do
    Repo.get!(Provider, id)
  end

  @doc """
  Gets a single provider by ID. Returns `nil` if not found.
  """
  @spec get_provider(binary()) :: Provider.t() | nil
  def get_provider(id) do
    Repo.get(Provider, id)
  end

  # ---------------------------------------------------------------------------
  # Create
  # ---------------------------------------------------------------------------

  @doc """
  Creates a provider for the given user.

  Accepts `user_id` and a map of attributes. If no `:priority` is supplied,
  it defaults to one past the current maximum for that user.

  ## Examples

      iex> create_provider(user_id, %{provider_type: :anthropic, name: "Claude", api_key: <<...>>})
      {:ok, %Provider{}}

      iex> create_provider(user_id, %{})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_provider(term(), map()) :: {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  def create_provider(user_id, attrs) do
    attrs =
      attrs
      |> Map.put(:user_id, user_id)
      |> maybe_assign_priority(user_id)

    %Provider{}
    |> Provider.changeset(attrs)
    |> Repo.insert()
  end

  # ---------------------------------------------------------------------------
  # Update / Delete
  # ---------------------------------------------------------------------------

  @doc """
  Updates an existing provider with the given attributes.

  ## Examples

      iex> update_provider(provider, %{name: "New Name"})
      {:ok, %Provider{}}
  """
  @spec update_provider(Provider.t(), map()) :: {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  def update_provider(%Provider{} = provider, attrs) do
    provider
    |> Provider.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a provider.

  ## Examples

      iex> delete_provider(provider)
      {:ok, %Provider{}}
  """
  @spec delete_provider(Provider.t()) :: {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  def delete_provider(%Provider{} = provider) do
    Repo.delete(provider)
  end

  # ---------------------------------------------------------------------------
  # Toggle / Reorder
  # ---------------------------------------------------------------------------

  @doc """
  Toggles the `enabled` boolean on a provider.

  If a second argument is given, it is used as the explicit new value;
  otherwise the current value is flipped.

  ## Examples

      iex> toggle_provider(provider)
      {:ok, %Provider{enabled: false}}

      iex> toggle_provider(provider, true)
      {:ok, %Provider{enabled: true}}
  """
  @spec toggle_provider(Provider.t(), boolean() | nil) ::
          {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  def toggle_provider(%Provider{} = provider, value \\ nil) do
    new_value = if is_nil(value), do: !provider.enabled, else: value

    provider
    |> Provider.changeset(%{enabled: new_value})
    |> Repo.update()
  end

  @doc """
  Bulk-updates priorities for a user's providers.

  Accepts a list of `{provider_id, new_priority}` tuples. All updates run
  inside a single transaction.

  ## Examples

      iex> reorder_providers(user_id, [{id1, 0}, {id2, 1}, {id3, 2}])
      {:ok, [%Provider{}, ...]}
  """
  @spec reorder_providers(term(), [{binary(), integer()}]) ::
          {:ok, [Provider.t()]} | {:error, term()}
  def reorder_providers(user_id, id_priority_pairs) when is_list(id_priority_pairs) do
    Repo.transaction(fn ->
      Enum.map(id_priority_pairs, fn {provider_id, priority} ->
        provider =
          Provider
          |> where([p], p.id == ^provider_id and p.user_id == ^user_id)
          |> Repo.one!()

        case provider |> Provider.changeset(%{priority: priority}) |> Repo.update() do
          {:ok, updated} -> updated
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Health / availability
  # ---------------------------------------------------------------------------

  @doc """
  Updates the health status and last_health_check_at timestamp for a provider.
  """
  @spec update_health(Provider.t(), atom()) :: {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  def update_health(%Provider{} = provider, status) do
    provider
    |> Provider.changeset(%{health_status: status, last_health_check_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Returns all providers available for a user — persisted DB records plus
  system-level providers derived from environment variables.

  Persisted providers take precedence: if a user has configured Anthropic
  via the UI, the system env-var fallback for Anthropic is excluded.
  """
  @spec all_available_providers(term()) :: [map()]
  def all_available_providers(user_id) do
    db_providers = list_providers(user_id)
    configured_types = MapSet.new(db_providers, & &1.provider_type)

    system_providers =
      SoundForge.LLM.Providers.SystemProviders.list_system_providers()
      |> Enum.reject(fn p -> MapSet.member?(configured_types, p.provider_type) end)

    db_providers ++ system_providers
  end

  # ---------------------------------------------------------------------------
  # Changeset helpers (for forms)
  # ---------------------------------------------------------------------------

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking provider changes in forms.
  """
  @spec change_provider(Provider.t(), map()) :: Ecto.Changeset.t()
  def change_provider(%Provider{} = provider, attrs \\ %{}) do
    Provider.changeset(provider, attrs)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp maybe_assign_priority(%{priority: p} = attrs, _user_id) when not is_nil(p), do: attrs

  defp maybe_assign_priority(attrs, user_id) do
    max_priority =
      Provider
      |> where([p], p.user_id == ^user_id)
      |> select([p], max(p.priority))
      |> Repo.one()

    Map.put(attrs, :priority, (max_priority || -1) + 1)
  end
end
