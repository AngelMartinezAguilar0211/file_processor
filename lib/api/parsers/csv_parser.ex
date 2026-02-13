defmodule API.FileProcessor.Parsers.CSVParser do
  # Define a NimbleCSV parser with comma separator and double-quote escape
  NimbleCSV.define(FileProcessorCSV, separator: ",", escape: "\"")

  # Parses raw CSV content provided as a binary string.
  def parse(content) when is_binary(content) do
    # Sanitize CSV content before parsing to fix malformed quotes
    safe_content = sanitize_content(content)

    # Parse CSV into a list of rows
    rows =
      safe_content
      |> FileProcessorCSV.parse_string(skip_headers: false)

    # Pattern match on parsed rows
    case rows do
      # Case: completely empty CSV
      [] ->
        {:ok, %{rows: [], errors: [%{line: 1, error: "Empty CSV"}]}}

      # Case: header + data rows
      [header | data] ->
        # Validate CSV header before processing rows
        if valid_header?(header) do
          # Start parsing data rows at line 2
          parse_rows(data, 2, [], [])
        else
          {:ok, %{rows: [], errors: [%{line: 1, error: "Invalid CSV header"}]}}
        end
    end
  rescue
    # Catch any unexpected exception thrown by NimbleCSV
    e ->
      {:error, "CSV parse error: #{Exception.message(e)}"}
  end

  # Validates that the CSV header matches the expected schema exactly
  defp valid_header?(header) do
    header == ["fecha", "producto", "categoria", "precio_unitario", "cantidad", "descuento"]
  end

  # Base case: no more rows to parse
  defp parse_rows([], _line, acc_rows, acc_errors) do
    # Reverse accumulators to preserve original order
    {:ok, %{rows: Enum.reverse(acc_rows), errors: Enum.reverse(acc_errors)}}
  end

  # Recursive case: parse current row and continue
  defp parse_rows([row | rest], line, acc_rows, acc_errors) do
    case parse_row(row) do
      # Successful row parsing
      {:ok, parsed} ->
        parse_rows(rest, line + 1, [parsed | acc_rows], acc_errors)

      # Row-level validation error
      {:error, reason} ->
        parse_rows(rest, line + 1, acc_rows, [%{line: line, error: reason} | acc_errors])
    end
  end

  # Parses a single CSV row with exactly six columns
  defp parse_row([date, product, category, unit_price, qty, discount]) do
    # Sequential validation using `with`
    with {:ok, d} <- parse_date(date),
         {:ok, price} <- parse_float(unit_price, "Invalid unit price"),
         {:ok, q} <- parse_int(qty, "Invalid quantity"),
         {:ok, disc} <- parse_float(discount, "Invalid discount"),
         :ok <- validate_positive(price, "Unit price must be positive"),
         :ok <- validate_positive(q, "Quantity must be positive"),
         :ok <- validate_discount(disc) do
      # Compute gross and net values
      gross = price * q
      net = gross * (1.0 - disc / 100.0)

      {:ok,
       %{
         date: d,
         product: product,
         category: category,
         unit_price: price,
         quantity: q,
         discount_pct: disc,
         gross: gross,
         net: net
       }}
    end
  end

  # Fallback case: row does not contain exactly 6 columns
  defp parse_row(_), do: {:error, "Row must have 6 columns"}

  # Parses and validates formatted date strings
  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> {:ok, d}
      _ -> {:error, "Invalid date format (expected YYYY-MM-DD)"}
    end
  end

  # Parses a float value from string
  defp parse_float(str, msg) do
    case Float.parse(str) do
      {v, ""} -> {:ok, v}
      _ -> {:error, msg}
    end
  end

  # Parses an integer value from string
  defp parse_int(str, msg) do
    case Integer.parse(str) do
      {v, ""} -> {:ok, v}
      _ -> {:error, msg}
    end
  end

  # Validates positive integer values
  defp validate_positive(v, _msg) when is_integer(v) and v > 0, do: :ok

  # Validates positive float values
  defp validate_positive(v, _msg) when is_float(v) and v > 0.0, do: :ok

  # Fallback for non-positive values
  defp validate_positive(_v, msg), do: {:error, msg}

  # Validates discount percentage range
  defp validate_discount(d) when is_float(d) and d >= 0.0 and d <= 100.0, do: :ok
  defp validate_discount(_), do: {:error, "Discount must be between 0 and 100"}

  # Sanitizes raw CSV content line by line.
  # This is used to fix malformed quoted fields before parsing.
  defp sanitize_content(content) do
    lines = String.split(content, "\n", trim: false)

    case lines do
      # Empty content fallback
      [] ->
        content

      # Preserve header and sanitize only data rows
      [header | rest] ->
        sanitized_rest =
          rest
          |> Enum.map(&sanitize_data_line/1)

        Enum.join([header | sanitized_rest], "\n")
    end
  end

  # Empty line remains empty
  defp sanitize_data_line(""), do: ""

  # Sanitizes a single CSV data line
  defp sanitize_data_line(line) do
    # Split into at most 6 fields to avoid breaking quoted content
    parts = String.split(line, ",", parts: 6)

    case parts do
      # Expected CSV structure
      [date, product, category, unit_price, qty, discount] ->
        safe_product = normalize_quotes_in_field(product)
        Enum.join([date, safe_product, category, unit_price, qty, discount], ",")

      # Fallback: return line unchanged
      _ ->
        line
    end
  end

  # Normalizes malformed quotes inside a CSV field
  defp normalize_quotes_in_field(field) do
    if String.contains?(field, "\"") do
      # Remove surrounding quotes
      trimmed =
        field
        |> String.trim_leading("\"")
        |> String.trim_trailing("\"")

      # Escape internal quotes according to CSV standard
      escaped = String.replace(trimmed, "\"", "\"\"")

      # Re-wrap field in quotes
      ~s("#{escaped}")
    else
      field
    end
  end
end
