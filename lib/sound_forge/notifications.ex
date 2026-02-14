defmodule SoundForge.Notifications do
  @moduledoc """
  ETS-backed notification store with PubSub broadcasting.

  Stores per-user notifications in an ETS table and broadcasts new
  notifications to `"notifications:\#{user_id}"` PubSub topics so that
  LiveViews can update in real time.

  ## Usage

      # Push a notification (broadcasts to subscribers)
      SoundForge.Notifications.push(user_id, %{
        type: :success,
        title: "Processing Complete",
        message: "Track 'My Song' has been separated into stems.",
        metadata: %{track_id: "abc-123"}
      })

      # List recent notifications
      SoundForge.Notifications.list(user_id)

      # Mark all as read
      SoundForge.Notifications.mark_read(user_id)

      # Get unread count
      SoundForge.Notifications.unread_count(user_id)
  """
  use GenServer

  @table :sfa_notifications
  @read_markers :sfa_notification_read_markers
  @default_limit 20

  # -- Public API --

  @doc """
  Starts the Notifications GenServer, which owns the ETS tables.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Pushes a notification for the given user.

  The `attrs` map should contain:
    - `:type` - one of `:info`, `:success`, `:warning`, `:error`
    - `:title` - short title string
    - `:message` - notification body string
    - `:metadata` - optional map of additional data (default `%{}`)

  Broadcasts `{:new_notification, notification}` to the user's PubSub topic.
  """
  @spec push(integer() | binary(), map()) :: :ok
  def push(user_id, attrs) when not is_nil(user_id) do
    id = Ecto.UUID.generate()
    now = DateTime.utc_now()
    timestamp_key = DateTime.to_unix(now, :microsecond)

    notification = %{
      id: id,
      type: attrs[:type] || :info,
      title: attrs[:title] || "",
      message: attrs[:message] || "",
      metadata: attrs[:metadata] || %{},
      read: false,
      inserted_at: now
    }

    if table_exists?(@table) do
      :ets.insert(@table, {{user_id, timestamp_key}, notification})
    end

    Phoenix.PubSub.broadcast(
      SoundForge.PubSub,
      "notifications:#{user_id}",
      {:new_notification, notification}
    )

    :ok
  end

  @doc """
  Returns the most recent notifications for the given user, newest first.
  """
  @spec list(integer() | binary(), non_neg_integer()) :: [map()]
  def list(user_id, limit \\ @default_limit) when not is_nil(user_id) do
    if not table_exists?(@table), do: throw(:no_table)

    # Match all entries for this user_id
    match_spec = [{{{user_id, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}]

    @table
    |> :ets.select(match_spec)
    |> Enum.sort_by(fn {ts, _notification} -> ts end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {_ts, notification} ->
      last_read = get_last_read(user_id)

      read =
        case last_read do
          nil -> false
          marker_dt -> DateTime.compare(notification.inserted_at, marker_dt) != :gt
        end

      %{notification | read: read}
    end)
  catch
    :no_table -> []
  end

  @doc """
  Marks all notifications as read for the given user by storing a timestamp marker.
  """
  @spec mark_read(integer() | binary()) :: :ok
  def mark_read(user_id) when not is_nil(user_id) do
    if table_exists?(@read_markers) do
      now = DateTime.utc_now()
      :ets.insert(@read_markers, {user_id, now})
    end

    :ok
  end

  @doc """
  Returns the count of unread notifications for the given user.
  """
  @spec unread_count(integer() | binary()) :: non_neg_integer()
  def unread_count(user_id) when not is_nil(user_id) do
    if not table_exists?(@table), do: throw(:no_table)

    last_read = get_last_read(user_id)

    match_spec = [{{{user_id, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}]

    @table
    |> :ets.select(match_spec)
    |> Enum.count(fn {_ts, notification} ->
      case last_read do
        nil -> true
        marker_dt -> DateTime.compare(notification.inserted_at, marker_dt) == :gt
      end
    end)
  catch
    :no_table -> 0
  end

  @doc """
  Subscribes the calling process to notifications for the given user.
  """
  @spec subscribe(integer() | binary()) :: :ok | {:error, term()}
  def subscribe(user_id) when not is_nil(user_id) do
    Phoenix.PubSub.subscribe(SoundForge.PubSub, "notifications:#{user_id}")
  end

  # -- GenServer callbacks --

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :ordered_set, :public, read_concurrency: true])

    read_markers =
      :ets.new(@read_markers, [:named_table, :set, :public, read_concurrency: true])

    {:ok, %{table: table, read_markers: read_markers}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -- Private helpers --

  defp table_exists?(table) do
    :ets.whereis(table) != :undefined
  end

  defp get_last_read(user_id) do
    if table_exists?(@read_markers) do
      case :ets.lookup(@read_markers, user_id) do
        [{^user_id, datetime}] -> datetime
        [] -> nil
      end
    else
      nil
    end
  end
end
