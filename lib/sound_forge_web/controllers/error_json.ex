defmodule SoundForgeWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  # If you want to customize a particular status code,
  # you may add your own clauses, such as:
  #
  # def render("500.json", _assigns) do
  #   %{errors: %{detail: "Internal Server Error"}}
  # end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
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
