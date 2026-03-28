defmodule SoundForge.CrateDigger.WhoSampledScraper do
  @moduledoc """
  Scrapes WhoSampled.com for sample information and caches results for 7 days.

  Uses Req (already in project deps) for HTTP and Floki for HTML parsing.
  Cache is stored in the `who_sampled_cache` table keyed by spotify_track_id.
  """

  require Logger

  alias SoundForge.CrateDigger.WhoSampledCache
  alias SoundForge.Repo

  @cache_ttl_days 7
  @base_url "https://www.whosampled.com"
  # Sample type keyword → normalized atom string
  @sample_type_map %{
    "direct sample" => "direct",
    "interpolation" => "interpolation",
    "replayed" => "replayed",
    "sampled" => "direct",
    "samples" => "direct",
    "contains samples" => "direct",
    "is sampled" => "direct"
  }

  @doc """
  Fetch sample data for a track identified by its Spotify track ID.

  Checks the 7-day cache first. If stale or missing, scrapes WhoSampled
  and stores the results. Returns `{:ok, [sample_map()]}` or `{:error, term()}`.

  Each sample map has keys: title, artist, year, sample_type, spotify_url, youtube_url.
  """
  @spec fetch_samples(String.t(), String.t(), String.t()) ::
          {:ok, [map()]} | {:error, term()}
  def fetch_samples(spotify_track_id, artist, title) do
    case get_cached(spotify_track_id) do
      {:hit, samples} ->
        {:ok, samples}

      :miss ->
        case scrape(artist, title) do
          {:ok, samples} ->
            store_cache(spotify_track_id, samples)
            {:ok, samples}

          {:error, :not_found} ->
            store_cache(spotify_track_id, [])
            {:ok, []}

          {:error, reason} = err ->
            Logger.warning("WhoSampledScraper failed for #{artist} - #{title}: #{inspect(reason)}")
            err
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Cache helpers
  # ---------------------------------------------------------------------------

  defp get_cached(spotify_track_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -@cache_ttl_days * 86_400, :second)

    case Repo.get_by(WhoSampledCache, spotify_track_id: spotify_track_id) do
      nil ->
        :miss

      %WhoSampledCache{fetched_at: fetched_at} = cached
      when not is_nil(fetched_at) ->
        if DateTime.compare(fetched_at, cutoff) == :gt do
          {:hit, cached.raw_data || []}
        else
          :miss
        end

      _ ->
        :miss
    end
  end

  defp store_cache(spotify_track_id, samples) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(WhoSampledCache, spotify_track_id: spotify_track_id) do
      nil ->
        %WhoSampledCache{}
        |> WhoSampledCache.changeset(%{
          spotify_track_id: spotify_track_id,
          raw_data: samples,
          fetched_at: now
        })
        |> Repo.insert(on_conflict: :replace_all, conflict_target: :spotify_track_id)

      existing ->
        existing
        |> WhoSampledCache.changeset(%{raw_data: samples, fetched_at: now})
        |> Repo.update()
    end
  end

  # ---------------------------------------------------------------------------
  # Scraping
  # ---------------------------------------------------------------------------

  defp scrape(artist, title) do
    query = URI.encode("#{artist} #{title}")
    search_url = "#{@base_url}/search/?q=#{query}&type=track"

    with {:ok, %Req.Response{status: 200, body: html}} <- req_get(search_url),
         {:ok, track_url} <- find_track_url(html, artist, title),
         {:ok, %Req.Response{status: 200, body: track_html}} <- req_get(track_url) do
      samples = parse_samples(track_html)
      {:ok, samples}
    else
      {:ok, %Req.Response{status: 429}} -> {:error, :rate_limited}
      {:ok, %Req.Response{status: 403}} -> {:error, :blocked}
      {:ok, %Req.Response{status: 404}} -> {:error, :not_found}
      {:ok, %Req.Response{status: status}} when status >= 500 -> {:error, {:server_error, status}}
      {:ok, %Req.Response{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, :no_match} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_track_url(html, artist, title) do
    # Parse search results and find best matching track URL
    case Floki.parse_document(html) do
      {:ok, doc} ->
        results = Floki.find(doc, ".trackResult, .searchResultItem, .track-result")

        match =
          Enum.find(results, fn node ->
            text = Floki.text(node) |> String.downcase()
            artist_match = String.contains?(text, String.downcase(artist))
            title_match = String.contains?(text, String.downcase(title))
            artist_match or title_match
          end)

        case match do
          nil ->
            # Try direct URL construction
            slug = build_slug(artist, title)
            {:ok, "#{@base_url}/#{slug}/"}

          node ->
            href = node |> Floki.find("a") |> Floki.attribute("href") |> List.first()

            if href do
              {:ok, "#{@base_url}#{href}"}
            else
              {:error, :no_match}
            end
        end

      _ ->
        {:error, :parse_error}
    end
  end

  defp parse_samples(html) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        # WhoSampled uses .sampleEntry, .sample-row, or similar selectors
        entries =
          Floki.find(
            doc,
            ".sampleEntry, .sample-item, [class*='sample'], .trackEntry, .connectedTrack"
          )

        if Enum.empty?(entries) do
          # Fallback: look for track links in sample sections
          parse_samples_fallback(doc)
        else
          Enum.map(entries, &parse_sample_node/1) |> Enum.reject(&is_nil/1)
        end

      _ ->
        []
    end
  end

  defp parse_samples_fallback(doc) do
    # Look for section headers that indicate sample usage, then grab track info nearby
    sections = Floki.find(doc, "h3, h4, .section-title")

    sample_sections =
      Enum.filter(sections, fn node ->
        text = Floki.text(node) |> String.downcase()
        String.contains?(text, "sampl") or String.contains?(text, "interpolat")
      end)

    if Enum.empty?(sample_sections) do
      []
    else
      # Grab track entries from the page
      doc
      |> Floki.find("a[href*='/sample/'], a[href*='/track/']")
      |> Enum.take(20)
      |> Enum.map(fn link ->
        _href = link |> Floki.attribute("href") |> List.first() || ""
        text = Floki.text(link)

        %{
          "title" => String.trim(text),
          "artist" => "",
          "year" => nil,
          "sample_type" => "direct",
          "spotify_url" => nil,
          "youtube_url" => nil
        }
      end)
      |> Enum.reject(&(&1["title"] == ""))
    end
  end

  defp parse_sample_node(node) do
    title_node = Floki.find(node, ".trackName, .title, h4, strong") |> List.first()
    artist_node = Floki.find(node, ".artistName, .artist, .byArtist") |> List.first()
    year_node = Floki.find(node, ".year, .releaseYear, time") |> List.first()
    type_node = Floki.find(node, ".sampleType, .connType, .sample-type") |> List.first()

    title = if title_node, do: Floki.text(title_node) |> String.trim(), else: ""
    artist = if artist_node, do: Floki.text(artist_node) |> String.trim(), else: ""
    year = if year_node, do: parse_year(Floki.text(year_node)), else: nil
    raw_type = if type_node, do: Floki.text(type_node) |> String.downcase() |> String.trim(), else: ""
    sample_type = normalize_sample_type(raw_type)

    links = Floki.find(node, "a")

    spotify_url =
      links
      |> Enum.find_value(fn link ->
        href = link |> Floki.attribute("href") |> List.first() || ""
        if String.contains?(href, "spotify.com"), do: href
      end)

    youtube_url =
      links
      |> Enum.find_value(fn link ->
        url = link |> Floki.attribute("href") |> List.first() || ""
        if String.contains?(url, "youtube.com") or String.contains?(url, "youtu.be"), do: url
      end)

    if title == "" do
      nil
    else
      %{
        "title" => title,
        "artist" => artist,
        "year" => year,
        "sample_type" => sample_type,
        "spotify_url" => spotify_url,
        "youtube_url" => youtube_url
      }
    end
  end

  defp parse_year(text) do
    case Regex.run(~r/\d{4}/, text) do
      [year] -> String.to_integer(year)
      _ -> nil
    end
  end

  defp normalize_sample_type(raw) do
    Enum.find_value(@sample_type_map, "other", fn {key, val} ->
      if String.contains?(raw, key), do: val
    end)
  end

  defp build_slug(artist, title) do
    slugify = fn s ->
      s
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.trim("-")
    end

    "#{slugify.(artist)}/#{slugify.(title)}"
  end

  defp req_get(url) do
    Req.get(url,
      headers: [
        {"User-Agent",
         "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"},
        {"Accept", "text/html,application/xhtml+xml"}
      ],
      redirect: true,
      receive_timeout: 10_000
    )
  end
end
