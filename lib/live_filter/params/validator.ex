defmodule LiveFilter.Params.Validator do
  @moduledoc """
  Validates parsed filters for operator validity, value length limits, and list size limits.
  """

  alias LiveFilter.Filter

  @max_value_length 500
  @max_list_size 100

  @doc """
  Validates a list of filters. Returns `:ok` or `{:error, reason}`.
  """
  @spec validate([Filter.t()]) :: :ok | {:error, term()}
  def validate(filters) when is_list(filters) do
    Enum.reduce_while(filters, :ok, fn filter, :ok ->
      case validate_filter(filter) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp validate_filter(%Filter{} = filter) do
    with :ok <- validate_operator(filter) do
      validate_value(filter)
    end
  end

  defp validate_operator(%Filter{operator: op, config: config}) do
    if op in config.operators do
      :ok
    else
      {:error, {:invalid_operator, op, config.field}}
    end
  end

  defp validate_value(%Filter{value: value}) when is_binary(value) do
    if String.length(value) > @max_value_length do
      {:error, {:value_too_long, String.length(value), @max_value_length}}
    else
      :ok
    end
  end

  defp validate_value(%Filter{value: values}) when is_list(values) do
    if length(values) > @max_list_size do
      {:error, {:list_too_large, length(values), @max_list_size}}
    else
      :ok
    end
  end

  defp validate_value(_filter), do: :ok
end
