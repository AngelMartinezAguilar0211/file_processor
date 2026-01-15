defmodule FileProcessor.Metrics.JSONMetrics do
  # Computes all JSON-related metrics from a decoded JSON map.
  #
  # Expected structure:
  # - "usuarios": list of user objects
  # - "sesiones": list of session objects
  def compute(%{} = json) do
    # Extract users and sessions from JSON, defaulting to empty lists
    users = Map.get(json, "usuarios", [])
    sessions = Map.get(json, "sesiones", [])

    # Count total number of users
    total_users = length(users)

    # Count active and inactive users
    {active, inactive} =
      Enum.reduce(users, {0, 0}, fn u, {a, i} ->
        case Map.get(u, "activo", false) do
          true -> {a + 1, i}
          false -> {a, i + 1}
        end
      end)

    # Compute average session duration (in seconds)
    avg_session_seconds =
      case sessions do
        # No sessions: avoid division by zero
        [] ->
          0.0

        _ ->
          total =
            Enum.reduce(sessions, 0, fn s, acc ->
              # Ignore negative or missing durations
              acc + max(0, Map.get(s, "duracion_segundos", 0))
            end)

          total / length(sessions)
      end

    # Compute total number of pages visited across all sessions
    total_pages =
      Enum.reduce(sessions, 0, fn s, acc ->
        # Ignore negative or missing page counts
        acc + max(0, Map.get(s, "paginas_visitadas", 0))
      end)

    # Compute the top 5 most frequent user actions
    top_actions =
      sessions
      |> Enum.flat_map(fn s ->
        # Extract actions list from each session
        Map.get(s, "acciones", [])
      end)
      |> Enum.reduce(%{}, fn action, acc ->
        # Count occurrences of each action
        Map.update(acc, action, 1, &(&1 + 1))
      end)
      |> Enum.sort_by(fn {_k, v} -> -v end)
      |> Enum.take(5)
      |> Enum.map(fn {k, v} ->
        %{action: k, count: v}
      end)

    # Compute peak hour of activity based on session start times
    peak_hour =
      sessions
      |> Enum.map(&Map.get(&1, "inicio"))
      |> Enum.filter(&is_binary/1)
      |> Enum.reduce(%{}, fn iso, acc ->
        case DateTime.from_iso8601(iso) do
          # Valid timestamp
          {:ok, dt, _offset} ->
            Map.update(acc, dt.hour, 1, &(&1 + 1))

          # Ignore invalid timestamps
          _ ->
            acc
        end
      end)
      |> peak_hour_from_map()

    # Return all computed metrics as a map
    %{
      total_users: total_users,
      active_users: active,
      inactive_users: inactive,
      avg_session_seconds: avg_session_seconds,
      total_pages: total_pages,
      top_actions: top_actions,
      peak_hour: peak_hour
    }
  end

  # Returns nil when no peak hour data is available
  defp peak_hour_from_map(map) when map == %{}, do: nil

  # Returns the hour with the highest number of sessions
  defp peak_hour_from_map(map) do
    {hour, count} = Enum.max_by(map, fn {_h, c} -> c end)
    %{hour: hour, sessions: count}
  end
end
