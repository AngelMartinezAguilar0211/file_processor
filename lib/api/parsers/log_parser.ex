defmodule FileProcessor.Parsers.LogParser do
  # Regular expression used to parse log lines.
  # Expected format:
  # YYYY-MM-DD HH:MM:SS [LEVEL] [COMPONENT] Message
  @line_regex ~r/^(?<date>\d{4}-\d{2}-\d{2})\s+(?<time>\d{2}:\d{2}:\d{2})\s+\[(?<level>[A-Z]+)\]\s+\[(?<component>[^\]]+)\]\s+(?<message>.*)$/

  # Represents a successfully parsed log entry
  @type log_entry :: %{
          timestamp: NaiveDateTime.t(),
          level: String.t(),
          component: String.t(),
          message: String.t()
        }

  # Represents a parsing error associated with a specific line
  @type parse_error :: %{line: pos_integer(), error: String.t()}

  # Parses raw log content.
  @spec parse(any()) ::
          {:ok, %{entries: [log_entry()], errors: [parse_error()]}}
          | {:error, String.t()}
  def parse(content) when is_binary(content) do
    try do
      # Split content into lines while preserving empty lines
      lines = String.split(content, "\n", trim: false)

      # Start recursive parsing at line number 1
      parse_lines(lines, 1, [], [])
    rescue
      # Catch unexpected runtime errors
      e ->
        {:error, "Log parse error: #{Exception.message(e)}"}
    end
  end

  # Fallback clause for invalid input types
  def parse(_content) do
    {:error, "Log content must be a binary"}
  end

  # Base case: no more lines to process
  defp parse_lines([], _line, acc_entries, acc_errors) do
    # Reverse accumulators to preserve original order
    {:ok, %{entries: Enum.reverse(acc_entries), errors: Enum.reverse(acc_errors)}}
  end

  # Recursive case: process current line and continue
  defp parse_lines([line | rest], n, acc_entries, acc_errors) do
    cond do
      # Ignore empty or whitespace-only lines
      String.trim(line) == "" ->
        parse_lines(rest, n + 1, acc_entries, acc_errors)

      true ->
        # Attempt to match the log line against the expected format
        case Regex.named_captures(@line_regex, line) do
          # Line does not match expected format
          nil ->
            parse_lines(rest, n + 1, acc_entries, [
              %{line: n, error: "Invalid log format"} | acc_errors
            ])

          # Line matches expected format
          %{
            "date" => d,
            "time" => t,
            "level" => level,
            "component" => comp,
            "message" => msg
          } ->
            # Validate and build timestamp
            with {:ok, ts} <- parse_timestamp(d, t) do
              # Build structured log entry
              entry = %{
                timestamp: ts,
                level: level,
                component: comp,
                message: msg
              }

              parse_lines(rest, n + 1, [entry | acc_entries], acc_errors)
            else
              # Timestamp parsing failed
              {:error, reason} ->
                parse_lines(rest, n + 1, acc_entries, [%{line: n, error: reason} | acc_errors])
            end
        end
    end
  end

  # Parses date and time strings into a NaiveDateTime
  defp parse_timestamp(date, time) do
    case NaiveDateTime.from_iso8601("#{date} #{time}") do
      {:ok, ts} -> {:ok, ts}
      _ -> {:error, "Invalid timestamp"}
    end
  end
end
