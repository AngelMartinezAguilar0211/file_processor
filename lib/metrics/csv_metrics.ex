defmodule FileProcessor.Metrics.CSVMetrics do
  # Computes all CSV-related metrics from a list of parsed rows.
  # Each row is expected to be a map containing:
  # :date, :product, :category, :quantity, :discount_pct, :net
  def compute(rows) when is_list(rows) do
    # Compute total sales by summing net values
    total_sales =
      Enum.reduce(rows, 0.0, fn r, acc ->
        acc + r.net
      end)

    # Build a set of product names to count unique products
    # The set itself is not returned, only its size is exposed as a metric.
    products_set =
      rows
      |> Enum.map(& &1.product)
      |> MapSet.new()

    # Count unique products
    unique_products = MapSet.size(products_set)

    # Determine the top-selling product by total quantity sold
    top_product =
      rows
      |> Enum.reduce(%{}, fn r, acc ->
        Map.update(acc, r.product, r.quantity, &(&1 + r.quantity))
      end)
      |> max_by_value()

    # Determine the top category by total net revenue
    top_category =
      rows
      |> Enum.reduce(%{}, fn r, acc ->
        Map.update(acc, r.category, r.net, &(&1 + r.net))
      end)
      |> max_by_value()

    # Compute average discount percentage
    avg_discount =
      case rows do
        # No rows: avoid division by zero
        [] ->
          0.0

        _ ->
          Enum.reduce(rows, 0.0, fn r, acc -> acc + r.discount_pct end) / length(rows)
      end

    # Compute date range (min and max dates)
    date_range =
      case rows do
        # No rows: no date range available
        [] ->
          {nil, nil}

        _ ->
          dates = Enum.map(rows, & &1.date)
          {Enum.min(dates), Enum.max(dates)}
      end

    # Return all computed metrics as a map
    %{
      total_sales: total_sales,
      unique_products: unique_products,
      top_product: top_product,
      top_category: top_category,
      avg_discount_pct: avg_discount,
      date_range: date_range
    }
  end

  # Returns nil when the map is empty
  defp max_by_value(map) when map == %{}, do: nil

  # Returns the key-value pair with the highest value
  # formatted as %{name: key, value: value}
  defp max_by_value(map) do
    {k, v} = Enum.max_by(map, fn {_k, v} -> v end)
    %{name: k, value: v}
  end
end
