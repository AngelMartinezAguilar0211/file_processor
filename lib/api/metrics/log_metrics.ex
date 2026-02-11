defmodule API.FileProcessor.Metrics.LogMetrics do
  # Severity levels considered critical for analysis
  @critical_levels ["FATAL", "ERROR"]

  # Computes all log-related metrics from a list of parsed log entries.
  # Each entry is expected to be a map containing:
  # :timestamp, :level, :component, :message
  def compute(entries) when is_list(entries) do
    # Total number of log entries
    total = length(entries)

    # Count entries grouped by log level
    by_level =
      Enum.reduce(entries, %{}, fn e, acc ->
        Map.update(acc, e.level, 1, &(&1 + 1))
      end)

    # Count entries grouped by hour of day
    by_hour =
      Enum.reduce(entries, %{}, fn e, acc ->
        Map.update(acc, e.timestamp.hour, 1, &(&1 + 1))
      end)

    # Filter only critical log entries (ERROR, FATAL)
    error_entries =
      Enum.filter(entries, fn e -> e.level in @critical_levels end)

    # Compute the most frequent error messages (top 5)
    top_error_messages =
      error_entries
      |> Enum.reduce(%{}, fn e, acc ->
        Map.update(acc, e.message, 1, &(&1 + 1))
      end)
      |> Enum.sort_by(fn {_k, v} -> -v end)
      |> Enum.take(5)
      |> Enum.map(fn {k, v} -> %{message: k, count: v} end)

    # Compute the component with the highest number of critical errors
    top_error_components =
      error_entries
      |> Enum.reduce(%{}, fn e, acc ->
        Map.update(acc, e.component, 1, &(&1 + 1))
      end)
      |> max_by_value()

    # Compute time gaps (in seconds) between consecutive critical errors
    critical_gaps =
      error_entries
      |> Enum.sort_by(& &1.timestamp)
      |> gaps_seconds()

    # Build normalized error message patterns for recurrence detection
    normalized_counts =
      error_entries
      |> Enum.map(&normalize_message/1)
      |> Enum.reduce(%{}, fn msg, acc ->
        Map.update(acc, msg, 1, &(&1 + 1))
      end)

    # Strict recurrent patterns (must appear at least twice)
    recurrent_patterns_strict =
      normalized_counts
      |> Enum.filter(fn {_k, v} -> v >= 2 end)
      |> Enum.sort_by(fn {_k, v} -> -v end)
      |> Enum.take(5)
      |> Enum.map(fn {k, v} -> %{pattern: k, count: v} end)

    # Fallback logic:
    # - If strict patterns exist, return them
    # - Else, return the most frequent pattern (even if it appears once)
    # - Else, return an empty list
    recurrent_patterns =
      cond do
        recurrent_patterns_strict != [] ->
          recurrent_patterns_strict

        map_size(normalized_counts) > 0 ->
          normalized_counts
          |> Enum.sort_by(fn {_k, v} -> -v end)
          |> Enum.take(1)
          |> Enum.map(fn {k, v} -> %{pattern: k, count: v} end)

        true ->
          []
      end

    # Return all computed log metrics
    %{
      total_entries: total,
      by_level: by_level,
      by_hour: by_hour,
      top_error_messages: top_error_messages,
      top_error_component: top_error_components,
      critical_error_gaps_seconds: critical_gaps,
      recurrent_error_patterns: recurrent_patterns
    }
  end

  # Returns nil when the input map is empty
  defp max_by_value(map) when map == %{}, do: nil

  # Returns the key-value pair with the highest value
  # formatted as %{name: key, value: value}
  defp max_by_value(map) do
    {k, v} = Enum.max_by(map, fn {_k, v} -> v end)
    %{name: k, value: v}
  end

  # No gaps available (zero or one error)
  defp gaps_seconds([]), do: %{count: 0, avg: 0.0, min: nil, max: nil}
  defp gaps_seconds([_one]), do: %{count: 0, avg: 0.0, min: nil, max: nil}

  # Compute gaps between consecutive timestamps (in seconds)
  defp gaps_seconds(sorted) do
    gaps =
      sorted
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] ->
        NaiveDateTime.diff(b.timestamp, a.timestamp, :second)
      end)

    %{
      count: length(gaps),
      avg: Enum.sum(gaps) / max(1, length(gaps)),
      min: Enum.min(gaps),
      max: Enum.max(gaps)
    }
  end

  # Normalize error messages to detect recurring patterns
  # - Replace numbers with a placeholder
  # - Normalize whitespace
  # - Trim leading and trailing spaces
  defp normalize_message(%{message: msg}) do
    msg
    |> String.replace(~r/\d+/, "<num>")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
