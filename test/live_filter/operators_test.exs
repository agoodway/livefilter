defmodule LiveFilter.OperatorsTest do
  use ExUnit.Case

  alias LiveFilter.Operators

  describe "label/1" do
    test "returns label for :in operator" do
      assert Operators.label(:in) == "is any of"
    end

    test "returns label for :not_in operator" do
      assert Operators.label(:not_in) == "is none of"
    end

    test "returns label for :eq operator" do
      assert Operators.label(:eq) == "is"
    end

    test "returns label for :neq operator" do
      assert Operators.label(:neq) == "is not"
    end
  end

  describe "value_mode/1" do
    test "returns :multi for :in operator" do
      assert Operators.value_mode(:in) == :multi
    end

    test "returns :multi for :not_in operator" do
      assert Operators.value_mode(:not_in) == :multi
    end

    test "returns :multi for :ov (overlap) operator" do
      assert Operators.value_mode(:ov) == :multi
    end

    test "returns :multi for :cs (contains) operator" do
      assert Operators.value_mode(:cs) == :multi
    end

    test "returns :multi for :cd (contained by) operator" do
      assert Operators.value_mode(:cd) == :multi
    end

    test "returns :single for :eq operator" do
      assert Operators.value_mode(:eq) == :single
    end

    test "returns :single for :neq operator" do
      assert Operators.value_mode(:neq) == :single
    end

    test "returns :single for comparison operators" do
      assert Operators.value_mode(:gt) == :single
      assert Operators.value_mode(:gte) == :single
      assert Operators.value_mode(:lt) == :single
      assert Operators.value_mode(:lte) == :single
    end

    test "returns :single for text operators" do
      assert Operators.value_mode(:ilike) == :single
      assert Operators.value_mode(:like) == :single
    end
  end

  describe "options_for_type/1" do
    test "returns operators for :select type" do
      options = Operators.options_for_type(:select)
      assert {:eq, "is"} in options
      assert {:neq, "is not"} in options
    end

    test "returns operators for :multi_select type" do
      options = Operators.options_for_type(:multi_select)
      assert {:ov, "contains any"} in options
      assert {:cs, "contains all"} in options
    end
  end
end
