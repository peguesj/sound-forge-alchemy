defmodule SoundForgeWeb.API.SSE do
  @moduledoc """
  Shared helpers for Server-Sent Event responses over Plug chunked conns.
  """

  import Plug.Conn

  @keepalive_interval_ms 25_000

  @spec keepalive_interval() :: pos_integer()
  def keepalive_interval, do: @keepalive_interval_ms

  @doc "Sets SSE headers and starts the chunked response."
  @spec prepare(Plug.Conn.t()) :: Plug.Conn.t()
  def prepare(conn) do
    conn
    |> put_resp_header("content-type", "text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("connection", "keep-alive")
    |> send_chunked(200)
  end

  @doc """
  Sends one SSE data frame with the JSON-encoded payload.
  Returns `{:error, conn}` when the client has disconnected.
  """
  @spec send_event(Plug.Conn.t(), term()) :: {:ok, Plug.Conn.t()} | {:error, Plug.Conn.t()}
  def send_event(conn, payload) do
    case chunk(conn, "data: #{Jason.encode!(payload)}\n\n") do
      {:ok, conn} -> {:ok, conn}
      {:error, _reason} -> {:error, conn}
    end
  end

  @doc "Sends an SSE comment frame to keep the connection alive."
  @spec send_keepalive(Plug.Conn.t()) :: {:ok, Plug.Conn.t()} | {:error, Plug.Conn.t()}
  def send_keepalive(conn) do
    case chunk(conn, ": keepalive\n\n") do
      {:ok, conn} -> {:ok, conn}
      {:error, _reason} -> {:error, conn}
    end
  end
end
