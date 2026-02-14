defmodule LiveFilter.OptionHelpersTest do
  use ExUnit.Case, async: true

  alias LiveFilter.OptionHelpers

  describe "resolve_options/1" do
    test "returns static options list" do
      config = %{options: ["a", "b", "c"]}
      assert OptionHelpers.resolve_options(config) == ["a", "b", "c"]
    end

    test "returns tuple options list" do
      config = %{options: [{"Label A", "a"}, {"Label B", "b"}]}
      assert OptionHelpers.resolve_options(config) == [{"Label A", "a"}, {"Label B", "b"}]
    end

    test "calls options_fn when function provided" do
      config = %{options_fn: fn -> ["x", "y", "z"] end}
      assert OptionHelpers.resolve_options(config) == ["x", "y", "z"]
    end

    test "prefers options over options_fn when both present" do
      config = %{options: ["static"], options_fn: fn -> ["dynamic"] end}
      assert OptionHelpers.resolve_options(config) == ["static"]
    end

    test "returns empty list when neither provided" do
      assert OptionHelpers.resolve_options(%{}) == []
    end

    test "returns empty list for nil options" do
      assert OptionHelpers.resolve_options(%{options: nil}) == []
    end
  end

  describe "opt_value/1" do
    test "extracts value from {label, value} tuple" do
      assert OptionHelpers.opt_value({"Active", "active"}) == "active"
    end

    test "extracts value from tuple with atom value" do
      assert OptionHelpers.opt_value({"Pending", :pending}) == :pending
    end

    test "extracts value from tuple with integer value" do
      assert OptionHelpers.opt_value({"One", 1}) == 1
    end

    test "returns raw value for string" do
      assert OptionHelpers.opt_value("active") == "active"
    end

    test "returns raw value for atom" do
      assert OptionHelpers.opt_value(:active) == :active
    end

    test "returns raw value for integer" do
      assert OptionHelpers.opt_value(42) == 42
    end
  end

  describe "opt_value_string/1" do
    test "converts tuple value to string" do
      assert OptionHelpers.opt_value_string({"Active", :active}) == "active"
    end

    test "converts integer tuple value to string" do
      assert OptionHelpers.opt_value_string({"One", 1}) == "1"
    end

    test "converts atom to string" do
      assert OptionHelpers.opt_value_string(:active) == "active"
    end

    test "converts integer to string" do
      assert OptionHelpers.opt_value_string(123) == "123"
    end

    test "returns string as-is" do
      assert OptionHelpers.opt_value_string("active") == "active"
    end
  end

  describe "opt_label/1" do
    test "extracts label from {label, value} tuple" do
      assert OptionHelpers.opt_label({"Active", "active"}) == "Active"
    end

    test "extracts label from tuple with atom label" do
      assert OptionHelpers.opt_label({:active, "active"}) == :active
    end

    test "returns raw value for string" do
      assert OptionHelpers.opt_label("active") == "active"
    end

    test "returns raw value for atom" do
      assert OptionHelpers.opt_label(:active) == :active
    end

    test "returns raw value for integer" do
      assert OptionHelpers.opt_label(42) == 42
    end
  end

  describe "opt_label_display/1" do
    test "returns tuple label as string" do
      assert OptionHelpers.opt_label_display({"Active", "active"}) == "Active"
    end

    test "converts atom label to string" do
      assert OptionHelpers.opt_label_display({:active_label, "active"}) == "active_label"
    end

    test "capitalizes lowercase string" do
      assert OptionHelpers.opt_label_display("active") == "Active"
    end

    test "capitalizes atom value" do
      assert OptionHelpers.opt_label_display(:pending) == "Pending"
    end

    test "converts integer to string" do
      assert OptionHelpers.opt_label_display(42) == "42"
    end

    test "handles already capitalized string" do
      assert OptionHelpers.opt_label_display("Active") == "Active"
    end

    test "handles underscore strings" do
      assert OptionHelpers.opt_label_display("in_progress") == "In_progress"
    end
  end
end
