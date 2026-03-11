defmodule FileProcessorWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use FileProcessorWeb, :html

  embed_templates "page_html/*"

  @doc """
  Extracts the executive summary section from the report content.
  """
  def extract_summary_section(content) do
    # Locates the "EXECUTIVE SUMMARY" section within the report
    case String.split(content, "EXECUTIVE SUMMARY") do
      [_before, remainder] ->
        # Extracts content up to the next dashed separator line
        remainder
        |> String.split(
          "--------------------------------------------------------------------------------"
        )
        |> List.first()
        |> String.trim()

      _ ->
        # Returns the first 20 lines as a fallback if the section is not found
        content
        |> String.split("\n")
        |> Enum.take(20)
        |> Enum.join("\n")
    end
  end
end

