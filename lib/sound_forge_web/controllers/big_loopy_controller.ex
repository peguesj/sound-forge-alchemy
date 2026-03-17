defmodule SoundForgeWeb.BigLoopyController do
  @moduledoc """
  Controller for BigLoopy HTTP actions: ZIP download for completed AlchemySets.
  """
  use SoundForgeWeb, :controller

  alias SoundForge.BigLoopy

  @doc """
  GET /alchemy/:id/download

  Serves the ZIP archive for a completed AlchemySet.
  Returns 404 if not found, 422 if not yet complete, 200 with file otherwise.
  """
  def download(conn, %{"id" => id}) do
    user_id = conn.assigns[:current_user] && conn.assigns.current_user.id

    case BigLoopy.get_alchemy_set(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "AlchemySet not found"})

      %{user_id: owner_id} when not is_nil(user_id) and owner_id != user_id ->
        conn |> put_status(:forbidden) |> json(%{error: "Access denied"})

      alchemy_set ->
        case alchemy_set.zip_path do
          nil ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "ZIP not ready — pipeline may still be processing"})

          zip_path ->
            filename = "#{alchemy_set.name |> String.replace(~r/[^\w\-]/, "_")}.zip"

            conn
            |> put_resp_content_type("application/zip")
            |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
            |> send_file(200, zip_path)
        end
    end
  end
end
