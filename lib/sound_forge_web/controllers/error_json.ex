defmodule SoundForgeWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  def render("401.json", _assigns) do
    %{error: "Unauthorized", message: "Authentication required"}
  end

  def render("403.json", _assigns) do
    %{error: "Forbidden", message: "You do not have access to this resource"}
  end

  def render("404.json", _assigns) do
    %{error: "Not Found", message: "The requested resource was not found"}
  end

  def render("500.json", _assigns) do
    %{error: "Internal Server Error", message: "An unexpected error occurred"}
  end

  def render(template, assigns) do
    response = %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}

    # Include request_id from the x-request-id header for debugging
    case assigns do
      %{conn: conn} when is_map(conn) ->
        case Plug.Conn.get_resp_header(conn, "x-request-id") do
          [request_id | _] -> Map.put(response, :request_id, request_id)
          _ -> response
        end

      _ ->
        response
    end
  end
end
