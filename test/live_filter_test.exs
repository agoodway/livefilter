defmodule LiveFilterTest do
  use ExUnit.Case

  alias LiveFilter.{Filter, FilterConfig, Operators}

  describe "text/2" do
    test "returns text FilterConfig with defaults" do
      config = LiveFilter.text(:reference, label: "Reference")
      assert %FilterConfig{} = config
      assert config.field == :reference
      assert config.type == :text
      assert config.label == "Reference"
      assert config.operators == [:ilike, :eq, :neq, :like]
      assert config.default_operator == :ilike
    end

    test "supports always_on and custom_param" do
      config = LiveFilter.text(:search, always_on: true, custom_param: "search")
      assert config.always_on == true
      assert config.custom_param == "search"
    end

    test "auto-generates label from field name" do
      config = LiveFilter.text(:reference)
      assert config.label == "Reference"
    end
  end

  describe "number/2" do
    test "returns number FilterConfig with defaults" do
      config = LiveFilter.number(:amount, label: "Amount")
      assert config.type == :number
      assert config.operators == [:eq, :neq, :gt, :gte, :lt, :lte]
      assert config.default_operator == :eq
    end
  end

  describe "select/2" do
    test "returns select FilterConfig with options" do
      config = LiveFilter.select(:status, label: "Status", options: ~w(pending active shipped))
      assert config.type == :select
      assert config.operators == [:eq, :neq]
      assert config.default_operator == :eq
      assert config.options == ["pending", "active", "shipped"]
    end
  end

  describe "multi_select/2" do
    test "returns multi_select FilterConfig" do
      config = LiveFilter.multi_select(:tags, label: "Tags", options: ~w(urgent bug feature))
      assert config.type == :multi_select
      assert config.operators == [:cs, :ov]
      assert config.default_operator == :ov
      assert config.options == ["urgent", "bug", "feature"]
    end
  end

  describe "date/2" do
    test "returns date FilterConfig" do
      config = LiveFilter.date(:due_date, label: "Due Date")
      assert config.type == :date
      assert config.operators == [:eq, :gt, :gte, :lt, :lte]
      assert config.default_operator == :eq
    end
  end

  describe "date_range/2" do
    test "returns date_range FilterConfig" do
      config = LiveFilter.date_range(:inserted_at, label: "Created")
      assert config.type == :date_range
      assert config.operators == [:gte_lte]
      assert config.default_operator == :gte_lte
    end
  end

  describe "datetime/2" do
    test "returns datetime FilterConfig" do
      config = LiveFilter.datetime(:updated_at, label: "Updated")
      assert config.type == :datetime
      assert config.operators == [:eq, :gt, :gte, :lt, :lte]
      assert config.default_operator == :eq
    end
  end

  describe "boolean/2" do
    test "returns boolean FilterConfig" do
      config = LiveFilter.boolean(:urgent, label: "Urgent")
      assert config.type == :boolean
      assert config.operators == [:is]
      assert config.default_operator == :is
    end
  end

  describe "Filter.new/1" do
    test "creates filter with unique ID and config defaults" do
      config = LiveFilter.select(:status, label: "Status", options: ~w(pending active))
      filter = Filter.new(config)

      assert %Filter{} = filter
      assert is_binary(filter.id)
      assert filter.field == :status
      assert filter.operator == :eq
      assert filter.value == nil
      assert filter.config == config
    end

    test "generates unique IDs" do
      config = LiveFilter.text(:name, label: "Name")
      f1 = Filter.new(config)
      f2 = Filter.new(config)
      assert f1.id != f2.id
    end
  end

  describe "Filter.new/3" do
    test "creates filter with specific operator and value" do
      config = LiveFilter.select(:status, label: "Status", options: ~w(pending active))
      filter = Filter.new(config, :neq, "pending")

      assert filter.operator == :neq
      assert filter.value == "pending"
    end
  end

  describe "Operators.label/1" do
    test "returns human-readable labels" do
      assert Operators.label(:ilike) == "contains"
      assert Operators.label(:eq) == "is"
      assert Operators.label(:neq) == "is not"
      assert Operators.label(:gt) == "is greater than"
      assert Operators.label(:gte_lte) == "between"
    end

    test "falls back to atom string for unknown operators" do
      assert Operators.label(:unknown_op) == "unknown_op"
    end
  end

  describe "Operators.options_for_type/1" do
    test "returns options for each type" do
      assert [{:ilike, "contains"} | _] = Operators.options_for_type(:text)
      assert [{:eq, "is"} | _] = Operators.options_for_type(:number)
      assert [{:eq, "is"}, {:neq, "is not"}] = Operators.options_for_type(:select)
      assert [{:ov, "contains any"} | _] = Operators.options_for_type(:multi_select)
      assert [{:is, "is"}] = Operators.options_for_type(:boolean)
      assert [{:gte_lte, "between"}] = Operators.options_for_type(:date_range)
    end
  end
end
