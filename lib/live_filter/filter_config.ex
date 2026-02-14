defmodule LiveFilter.FilterConfig do
  @moduledoc """
  Defines a filterable field — its type, allowed operators, label, and options.
  """

  @type icon_fn :: (map() -> Phoenix.LiveView.Rendered.t()) | nil

  @type t :: %__MODULE__{
          field: atom(),
          type: LiveFilter.Types.filter_type(),
          label: String.t(),
          operators: [LiveFilter.Types.operator()],
          default_operator: LiveFilter.Types.operator(),
          options: [String.t() | {String.t(), String.t()}] | nil,
          options_fn: (-> [String.t() | {String.t(), String.t()}]) | nil,
          placeholder: String.t() | nil,
          always_on: boolean(),
          default_value: LiveFilter.Types.filter_value(),
          query_field: atom() | nil,
          custom_param: String.t() | nil,
          input_component: module() | nil,
          hide_label: boolean(),
          icon: icon_fn(),
          theme: atom() | nil,
          mode: :basic | :command | nil,
          removable: boolean(),
          search_threshold: non_neg_integer() | nil,
          date_presets: [atom()] | nil,
          # Boolean filter options
          true_label: String.t(),
          false_label: String.t(),
          any_label: String.t(),
          nullable: boolean(),
          # RadioGroup filter options
          style: :pills | :radios,
          inline_threshold: non_neg_integer(),
          # DateTime filter options
          time_format: :twelve_hour | :twenty_four_hour,
          minute_step: pos_integer()
        }

  defstruct [
    :field,
    :type,
    :label,
    :default_operator,
    :options,
    :options_fn,
    :placeholder,
    :default_value,
    :query_field,
    :custom_param,
    :input_component,
    :icon,
    :theme,
    :mode,
    :search_threshold,
    :date_presets,
    operators: [],
    always_on: false,
    default_visible: false,
    hide_label: false,
    removable: true,
    # Boolean filter options
    true_label: "Yes",
    false_label: "No",
    any_label: "Any",
    nullable: false,
    # RadioGroup filter options
    style: :pills,
    inline_threshold: 4,
    # DateTime filter options
    time_format: :twelve_hour,
    minute_step: 1
  ]
end
