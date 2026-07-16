defmodule SoundForge.LiveHarness.Catalog.Step do
  @moduledoc "A single live-harness verification step."

  @enforce_keys [:id, :criterion, :title, :kind]
  defstruct id: nil,
            criterion: nil,
            title: nil,
            kind: :route,
            method: :get,
            path: nil,
            request_body: nil,
            expected_statuses: [200],
            expected_text: [],
            accepted_redirect_paths: [],
            artifact_paths: [],
            acceptance: nil,
            warning_only: false

  @type kind :: :route | :api | :journey | :preflight | :artifact | :manual

  @type t :: %__MODULE__{
          id: String.t(),
          criterion: String.t(),
          title: String.t(),
          kind: kind(),
          method: :get | :post | :patch | :delete,
          path: String.t() | nil,
          request_body: map() | nil,
          expected_statuses: [pos_integer()],
          expected_text: [String.t()],
          accepted_redirect_paths: [String.t()],
          artifact_paths: [String.t()],
          acceptance: String.t() | nil,
          warning_only: boolean()
        }
end
