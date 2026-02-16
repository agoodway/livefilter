defmodule LiveFilter.Filter do
  @moduledoc """
  Represents an active filter instance with a unique ID, field, operator, value, and config reference.
  """

  alias LiveFilter.FilterConfig

  @type t :: %__MODULE__{
          id: String.t(),
          field: atom(),
          operator: LiveFilter.Types.operator(),
          value: LiveFilter.Types.filter_value(),
          config: FilterConfig.t()
        }

  defstruct [:id, :field, :operator, :value, :config]

  @doc """
  Creates a new Filter from a FilterConfig, using the config's default operator and nil value.
  """
  @spec new(FilterConfig.t()) :: t()
  def new(%FilterConfig{} = config) do
    %__MODULE__{
      id: stable_id(config.field),
      field: config.field,
      operator: config.default_operator,
      value: config.default_value,
      config: config
    }
  end

  @doc """
  Creates a new Filter from a FilterConfig with a specific operator and value.
  """
  @spec new(FilterConfig.t(), LiveFilter.Types.operator(), LiveFilter.Types.filter_value()) :: t()
  def new(%FilterConfig{} = config, operator, value) do
    %__MODULE__{
      id: stable_id(config.field),
      field: config.field,
      operator: operator,
      value: value,
      config: config
    }
  end

  defp stable_id(field) do
    Atom.to_string(field)
  end
end
