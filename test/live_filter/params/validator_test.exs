defmodule LiveFilter.Params.ValidatorTest do
  use ExUnit.Case

  alias LiveFilter.{Filter, FilterConfig}
  alias LiveFilter.Params.Validator

  defp make_filter(field, operator, value, opts \\ []) do
    operators = Keyword.get(opts, :operators, [operator])

    config = %FilterConfig{
      field: field,
      type: :text,
      label: to_string(field),
      operators: operators,
      default_operator: hd(operators),
      always_on: false
    }

    Filter.new(config, operator, value)
  end

  describe "validate/1 operator validation" do
    test "valid operator returns :ok" do
      filter = make_filter(:name, :ilike, "foo", operators: [:ilike, :eq])
      assert :ok = Validator.validate([filter])
    end

    test "invalid operator returns error" do
      filter = make_filter(:name, :gt, "foo", operators: [:ilike, :eq])
      assert {:error, {:invalid_operator, :gt, :name}} = Validator.validate([filter])
    end
  end

  describe "validate/1 string value limits" do
    test "string within limit returns :ok" do
      value = String.duplicate("a", 500)
      filter = make_filter(:name, :ilike, value)
      assert :ok = Validator.validate([filter])
    end

    test "string exceeding limit returns error" do
      value = String.duplicate("a", 501)
      filter = make_filter(:name, :ilike, value)
      assert {:error, {:value_too_long, 501, 500}} = Validator.validate([filter])
    end
  end

  describe "validate/1 list size limits" do
    test "list within limit returns :ok" do
      values = Enum.map(1..100, &to_string/1)
      filter = make_filter(:tags, :in, values)
      assert :ok = Validator.validate([filter])
    end

    test "list exceeding limit returns error" do
      values = Enum.map(1..101, &to_string/1)
      filter = make_filter(:tags, :in, values)
      assert {:error, {:list_too_large, 101, 100}} = Validator.validate([filter])
    end

    test "empty list returns :ok" do
      filter = make_filter(:tags, :in, [])
      assert :ok = Validator.validate([filter])
    end
  end

  describe "validate/1 non-string non-list values" do
    test "boolean value returns :ok" do
      filter = make_filter(:urgent, :is, true)
      assert :ok = Validator.validate([filter])
    end

    test "integer value returns :ok" do
      filter = make_filter(:amount, :eq, 42)
      assert :ok = Validator.validate([filter])
    end

    test "tuple value returns :ok" do
      filter = make_filter(:dates, :gte_lte, {"2024-01-01", "2024-12-31"})
      assert :ok = Validator.validate([filter])
    end
  end

  describe "validate/1 multiple filters" do
    test "all valid returns :ok" do
      f1 = make_filter(:name, :ilike, "foo")
      f2 = make_filter(:status, :eq, "active")
      assert :ok = Validator.validate([f1, f2])
    end

    test "first invalid halts with error" do
      f1 = make_filter(:name, :gt, "foo", operators: [:ilike])
      f2 = make_filter(:status, :eq, "active")
      assert {:error, {:invalid_operator, :gt, :name}} = Validator.validate([f1, f2])
    end

    test "second invalid returns error" do
      f1 = make_filter(:name, :ilike, "foo")
      f2 = make_filter(:status, :gt, "active", operators: [:eq])
      assert {:error, {:invalid_operator, :gt, :status}} = Validator.validate([f1, f2])
    end

    test "empty filter list returns :ok" do
      assert :ok = Validator.validate([])
    end
  end
end
