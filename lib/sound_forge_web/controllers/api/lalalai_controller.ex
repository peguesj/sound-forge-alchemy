defmodule SoundForgeWeb.API.LalalaiController do
  @moduledoc """
  Controller for lalal.ai quota and task management API routes.
  Provides quota checking, single-task cancellation, and bulk cancellation
  for authenticated users.
  """
  use SoundForgeWeb, :controller

  alias SoundForge.Audio.LalalAI

  action_fallback SoundForgeWeb.API.FallbackController

  @doc """
  GET /api/lalalai/quota

  Returns the remaining lalal.ai quota in minutes for the current user.
  Resolves the API key per user (user override or global fallback).
  """
  def quota(conn, _params) do
    user = conn.assigns.current_scope.user
    api_key = LalalAI.api_key_for_user(user.id)

    case api_key do
      nil ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "lalal.ai API key not configured"})

      key ->
        case get_quota_with_key(key) do
          {:ok, minutes} ->
            json(conn, %{minutes_left: minutes})

          {:error, {:http_error, status_code, _body}} ->
            conn
            |> put_status(:bad_gateway)
            |> json(%{error: "lalal.ai API returned HTTP #{status_code}"})

          {:error, reason} ->
            conn
            |> put_status(:bad_gateway)
            |> json(%{error: "Failed to fetch quota: #{inspect(reason)}"})
        end
    end
  end

  @doc """
  POST /api/lalalai/cancel

  Cancels a single lalal.ai separation task.
  Expects a JSON body with `task_id` (string).
  """
  def cancel(conn, %{"task_id" => task_id}) when is_binary(task_id) and task_id != "" do
    case LalalAI.cancel_task(task_id) do
      {:ok, result} ->
        json(conn, %{success: true, result: result})

      {:error, :api_key_missing} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "lalal.ai API key not configured"})

      {:error, {:http_error, status_code, _body}} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "lalal.ai API returned HTTP #{status_code}"})

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "Failed to cancel task: #{inspect(reason)}"})
    end
  end

  def cancel(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "task_id parameter is required"})
  end

  @doc """
  POST /api/lalalai/cancel-all

  Cancels all running lalal.ai separation tasks for the current account.
  """
  def cancel_all(conn, _params) do
    case LalalAI.cancel_all_tasks() do
      {:ok, result} ->
        json(conn, %{success: true, result: result})

      {:error, :api_key_missing} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "lalal.ai API key not configured"})

      {:error, {:http_error, status_code, _body}} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "lalal.ai API returned HTTP #{status_code}"})

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "Failed to cancel tasks: #{inspect(reason)}"})
    end
  end

  # Fetches quota using a specific API key (resolved per user).
  # This bypasses the module-level with_api_key/1 so we can use the
  # user-resolved key instead of the global Application env key.
  defp get_quota_with_key(key) do
    url = "https://www.lalal.ai/api/v1/limits/minutes_left/"

    result =
      Req.post(url,
        headers: [{"x-license-key", key}],
        json: %{},
        receive_timeout: 30_000
      )

    case result do
      {:ok, %{status: 200, body: %{"minutes_left" => minutes}}} when is_number(minutes) ->
        {:ok, minutes / 1.0}

      {:ok, %{status: 200, body: body}} ->
        {:error, {:unexpected_response, body}}

      {:ok, %{status: status_code, body: body}} ->
        {:error, {:http_error, status_code, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
