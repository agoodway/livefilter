defmodule LiveFilter.Components.Helpers do
  @moduledoc """
  Shared helper functions and icons for LiveFilter components.
  """
  use Phoenix.Component

  @doc """
  Compares two values for equality, handling type coercion between strings and integers.
  """
  def values_match?(a, b) when a == b, do: true
  def values_match?(a, b) when is_binary(a) and is_integer(b), do: a == to_string(b)
  def values_match?(a, b) when is_integer(a) and is_binary(b), do: to_string(a) == b
  def values_match?(_, _), do: false

  @doc """
  Renders a checkmark icon.
  """
  attr(:class, :string, default: "shrink-0 text-base-content")

  def check_icon(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class={@class} width="16" height="16" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
    </svg>
    """
  end

  @doc """
  Renders an X/close icon.
  """
  attr(:class, :string, default: "shrink-0")

  def x_icon(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class={@class} width="14" height="14" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
    </svg>
    """
  end

  @doc """
  Renders a left chevron icon.
  """
  attr(:class, :string, default: "shrink-0")

  def chevron_left_icon(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class={@class} width="16" height="16" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
    </svg>
    """
  end

  @doc """
  Renders a right chevron icon.
  """
  attr(:class, :string, default: "shrink-0")

  def chevron_right_icon(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class={@class} width="16" height="16" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
    </svg>
    """
  end
end
