defmodule LiveFilter.OptionHelpers do
  @moduledoc """
  Shared helpers for resolving and formatting filter options.

  Used by Bar component and individual input components to handle
  options in consistent formats: `["value1", "value2"]` or `[{"Label", "value"}]`.
  """

  @doc """
  Resolves options from a config struct.

  Supports both static options lists and dynamic options functions.

  ## Examples

      iex> resolve_options(%{options: ["a", "b"]})
      ["a", "b"]

      iex> resolve_options(%{options_fn: fn -> ["x", "y"] end})
      ["x", "y"]

      iex> resolve_options(%{})
      []
  """
  @spec resolve_options(map()) :: list()
  def resolve_options(%{options: options}) when is_list(options), do: options
  def resolve_options(%{options_fn: fun}) when is_function(fun, 0), do: fun.()
  def resolve_options(_), do: []

  @doc """
  Extracts the value from an option.

  Options can be simple values or `{label, value}` tuples.

  ## Examples

      iex> opt_value({"Active", "active"})
      "active"

      iex> opt_value("active")
      "active"
  """
  @spec opt_value(term()) :: term()
  def opt_value({_label, value}), do: value
  def opt_value(value), do: value

  @doc """
  Extracts the value from an option as a string.

  Used for comparisons in UI where values need to be strings.

  ## Examples

      iex> opt_value_string({"Active", :active})
      "active"

      iex> opt_value_string(123)
      "123"
  """
  @spec opt_value_string(term()) :: String.t()
  def opt_value_string({_label, value}), do: to_string(value)
  def opt_value_string(value), do: to_string(value)

  @doc """
  Extracts the label from an option.

  For tuples, returns the first element. For simple values, returns the value as-is.

  ## Examples

      iex> opt_label({"Active", "active"})
      "Active"

      iex> opt_label("active")
      "active"
  """
  @spec opt_label(term()) :: term()
  def opt_label({label, _value}), do: label
  def opt_label(value), do: value

  @doc """
  Extracts the label from an option with display formatting.

  Capitalizes string values that aren't already in tuple format.

  ## Examples

      iex> opt_label_display({"Active", "active"})
      "Active"

      iex> opt_label_display("active")
      "Active"

      iex> opt_label_display(:pending)
      "Pending"
  """
  @spec opt_label_display(term()) :: String.t()
  def opt_label_display({label, _value}), do: to_string(label)
  def opt_label_display(value) when is_binary(value), do: String.capitalize(value)
  def opt_label_display(value), do: value |> to_string() |> String.capitalize()
end
