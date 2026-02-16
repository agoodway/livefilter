defmodule LiveFilter.Params.SerializerTest do
  use ExUnit.Case

  alias LiveFilter.Filter
  alias LiveFilter.Params.Serializer

  defp make_filter(field, type, operator, value, opts \\ []) do
    config = apply(LiveFilter, type, [field, opts])
    Filter.new(config, operator, value)
  end

  describe "to_params/1" do
    test "serializes simple eq filter" do
      params =
        Serializer.to_params([make_filter(:status, :select, :eq, "active", options: ~w(active))])

      assert params == %{"status" => "eq.active"}
    end

    test "serializes neq filter" do
      params =
        Serializer.to_params([
          make_filter(:status, :select, :neq, "pending", options: ~w(pending))
        ])

      assert params == %{"status" => "neq.pending"}
    end

    test "serializes ilike with auto-wrapping" do
      params = Serializer.to_params([make_filter(:name, :text, :ilike, "foo")])
      assert params == %{"name" => "ilike.*foo*"}
    end

    test "ilike preserves existing wildcards" do
      params = Serializer.to_params([make_filter(:name, :text, :ilike, "*foo*")])
      assert params == %{"name" => "ilike.*foo*"}
    end

    test "ilike preserves partial wildcards" do
      params = Serializer.to_params([make_filter(:name, :text, :ilike, "*foo")])
      assert params == %{"name" => "ilike.*foo*"}
    end

    test "serializes IN list" do
      params =
        Serializer.to_params([
          make_filter(:tags, :multi_select, :in, ["urgent", "bug"], options: ~w(urgent bug))
        ])

      assert params == %{"tags" => "in.(urgent,bug)"}
    end

    test "serializes select :in filter with multiple values" do
      params =
        Serializer.to_params([
          make_filter(:status, :select, :in, ["active", "pending"],
            options: ~w(active pending shipped),
            operators: [:eq, :neq, :in, :not_in]
          )
        ])

      assert params == %{"status" => "in.(active,pending)"}
    end

    test "serializes select :not_in filter" do
      params =
        Serializer.to_params([
          make_filter(:status, :select, :not_in, ["draft"],
            options: ~w(draft active shipped),
            operators: [:eq, :neq, :in, :not_in]
          )
        ])

      assert params == %{"status" => "not_in.(draft)"}
    end

    test "serializes select :not_in filter with multiple values" do
      params =
        Serializer.to_params([
          make_filter(:status, :select, :not_in, ["draft", "cancelled"],
            options: ~w(draft active shipped cancelled),
            operators: [:eq, :neq, :in, :not_in]
          )
        ])

      assert params == %{"status" => "not_in.(draft,cancelled)"}
    end

    test "serializes boolean is.true" do
      params = Serializer.to_params([make_filter(:urgent, :boolean, :is, true)])
      assert params == %{"urgent" => "is.true"}
    end

    test "serializes boolean is.false" do
      params = Serializer.to_params([make_filter(:urgent, :boolean, :is, false)])
      assert params == %{"urgent" => "is.false"}
    end

    test "serializes date range as two params using and() syntax" do
      params =
        Serializer.to_params([
          make_filter(:inserted_at, :date_range, :gte_lte, {~D[2024-01-01], ~D[2024-02-01]})
        ])

      assert params == %{"and" => "(inserted_at.gte.2024-01-01,inserted_at.lte.2024-02-01)"}
    end

    test "serializes date range with only start using and() syntax" do
      params =
        Serializer.to_params([
          make_filter(:inserted_at, :date_range, :gte_lte, {~D[2024-01-01], nil})
        ])

      assert params == %{"and" => "(inserted_at.gte.2024-01-01)"}
    end

    test "excludes nil values" do
      params =
        Serializer.to_params([make_filter(:status, :select, :eq, nil, options: ~w(active))])

      assert params == %{}
    end

    test "excludes empty string values" do
      params = Serializer.to_params([make_filter(:name, :text, :ilike, "")])
      assert params == %{}
    end

    test "uses custom_param key when set" do
      config = LiveFilter.text(:title, custom_param: "search")
      filter = Filter.new(config, :ilike, "test")
      params = Serializer.to_params([filter])
      assert Map.has_key?(params, "search")
    end

    test "custom_param outputs raw value without operator prefix" do
      config = LiveFilter.text(:title, custom_param: "q")
      filter = Filter.new(config, :ilike, "angel")
      params = Serializer.to_params([filter])
      assert params == %{"q" => "angel"}
    end

    test "custom_param works with non-text filter types" do
      config = LiveFilter.select(:status, custom_param: "s", options: ~w(active pending))
      filter = Filter.new(config, :eq, "active")
      params = Serializer.to_params([filter])
      assert params == %{"s" => "active"}
    end

    test "custom_param handles numeric values" do
      config = LiveFilter.number(:amount, custom_param: "amt")
      filter = Filter.new(config, :eq, 100)
      params = Serializer.to_params([filter])
      assert params == %{"amt" => "100"}
    end

    test "serializes number filters" do
      params = Serializer.to_params([make_filter(:amount, :number, :gt, 100)])
      assert params == %{"amount" => "gt.100"}
    end

    test "serializes multiple filters" do
      filters = [
        make_filter(:status, :select, :eq, "active", options: ~w(active)),
        make_filter(:urgent, :boolean, :is, true)
      ]

      params = Serializer.to_params(filters)
      assert params == %{"status" => "eq.active", "urgent" => "is.true"}
    end
  end
end
