defmodule SoundForgeWeb.API.TrackerController do
  @moduledoc """
  Realtime tracker API: liveness, state, card ingest, and an SSE stream of
  full state snapshots broadcast on the `"tracker:events"` PubSub topic.
  """

  use SoundForgeWeb, :controller

  alias SoundForge.Tracker.Store
  alias SoundForgeWeb.API.SSE

  def health(conn, _params) do
    json(conn, %{online: true})
  end

  def state(conn, _params) do
    json(conn, Store.snapshot())
  end

  def create_card(conn, params) do
    card = Map.drop(params, ["_format"])

    case Store.add_card(card) do
      {:ok, snapshot} ->
        json(conn, %{ok: true, trackerStatus: %{cardCount: snapshot.card_count, online: true}})

      {:error, :invalid_card} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "invalid card"})
    end
  end

  def events(conn, params) do
    Phoenix.PubSub.subscribe(SoundForge.PubSub, Store.topic())

    conn = SSE.prepare(conn)

    case SSE.send_event(conn, Store.snapshot()) do
      {:ok, conn} ->
        if params["once"] == "true" do
          conn
        else
          stream_loop(conn)
        end

      {:error, conn} ->
        conn
    end
  end

  defp stream_loop(conn) do
    receive do
      {:tracker_snapshot, snapshot} ->
        case SSE.send_event(conn, snapshot) do
          {:ok, conn} -> stream_loop(conn)
          {:error, conn} -> conn
        end

      _other ->
        # Drop stray messages so the selective receive's mailbox stays bounded.
        stream_loop(conn)
    after
      SSE.keepalive_interval() ->
        case SSE.send_keepalive(conn) do
          {:ok, conn} -> stream_loop(conn)
          {:error, conn} -> conn
        end
    end
  end
end
