defmodule SoundForgeWeb.API.ChatController do
  @moduledoc """
  Chat bridge API: presence JSON, message posting, and an SSE stream of chat
  messages and presence changes broadcast on the `"chat:events"` PubSub topic.
  """

  use SoundForgeWeb, :controller

  alias SoundForge.Chat.Bridge
  alias SoundForgeWeb.API.SSE

  def presence(conn, _params) do
    json(conn, %{participants: Bridge.presence()})
  end

  def create_message(conn, params) do
    case Bridge.post_message(params) do
      {:ok, message} ->
        json(conn, %{ok: true, message: message})

      {:error, :invalid_message} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "sender and body are required"})
    end
  end

  def events(conn, params) do
    Phoenix.PubSub.subscribe(SoundForge.PubSub, Bridge.topic())

    conn = SSE.prepare(conn)

    initial = %{
      type: "init",
      participants: Bridge.presence(),
      messages: Bridge.messages()
    }

    case SSE.send_event(conn, initial) do
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
    result =
      receive do
        {:chat_message, message} ->
          SSE.send_event(conn, %{type: "message", message: message})

        {:chat_presence, participants} ->
          SSE.send_event(conn, %{type: "presence", participants: participants})

        _other ->
          # Drop stray messages so the selective receive's mailbox stays bounded.
          {:ok, conn}
      after
        SSE.keepalive_interval() ->
          SSE.send_keepalive(conn)
      end

    case result do
      {:ok, conn} -> stream_loop(conn)
      {:error, conn} -> conn
    end
  end
end
