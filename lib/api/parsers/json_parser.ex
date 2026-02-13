defmodule API.FileProcessor.Parsers.JSONParser do
  # Parses raw JSON content.
  def parse(content) when is_binary(content) do
    # Attempt to decode the JSON using Jason
    case Jason.decode(content) do
      # Successful decoding and root is a JSON object
      {:ok, %{} = map} ->
        {:ok, map}

      # Successful decoding but root element is NOT an object
      {:ok, _other} ->
        {:error, "JSON root must be an object"}

      # Decoding error
      {:error, err} ->
        {:error, "JSON decode error: #{Exception.message(err)}"}
    end
  end
end
