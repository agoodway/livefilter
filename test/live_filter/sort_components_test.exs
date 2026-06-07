defmodule LiveFilter.SortComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.Component
  import Phoenix.LiveViewTest
  alias LiveFilter.Sort
  alias LiveFilter.Sort.Entry

  defp sortable do
    [LiveFilter.sort_field(:clicks, default_direction: :desc), LiveFilter.sort_field(:name)]
  end

  describe "sort_header/1" do
    test "renders the label and a clickable button carrying the field" do
      html =
        render_component(&LiveFilter.SortComponents.sort_header/1,
          field: :clicks,
          label: "Clicks",
          sort: %Sort{},
          sortable_fields: sortable()
        )

      assert html =~ "Clicks"
      assert html =~ ~s(phx-click="lf_sort")
      assert html =~ ~s(phx-value-field="clicks")
    end

    test "reflects the active ascending state via aria-sort" do
      sort = %Sort{entries: [%Entry{field: :clicks, direction: :asc}]}

      html =
        render_component(&LiveFilter.SortComponents.sort_header/1,
          field: :clicks,
          label: "Clicks",
          sort: sort,
          sortable_fields: sortable()
        )

      assert html =~ ~s(aria-sort="ascending")
    end

    test "reflects the active descending state via aria-sort" do
      sort = %Sort{entries: [%Entry{field: :clicks, direction: :desc}]}

      html =
        render_component(&LiveFilter.SortComponents.sort_header/1,
          field: :clicks,
          label: "Clicks",
          sort: sort,
          sortable_fields: sortable()
        )

      assert html =~ ~s(aria-sort="descending")
    end

    test "an unsorted header is aria-sort=none" do
      html =
        render_component(&LiveFilter.SortComponents.sort_header/1,
          field: :clicks,
          label: "Clicks",
          sort: %Sort{},
          sortable_fields: sortable()
        )

      assert html =~ ~s(aria-sort="none")
    end

    test "honors a class override and a custom event name" do
      html =
        render_component(&LiveFilter.SortComponents.sort_header/1,
          field: :clicks,
          label: "Clicks",
          sort: %Sort{},
          sortable_fields: sortable(),
          class: "my-th",
          event: "sort_links"
        )

      assert html =~ "my-th"
      assert html =~ ~s(phx-click="sort_links")
    end

    test "an inner slot replaces the default label rendering" do
      assigns = %{
        sortable_fields: [
          LiveFilter.sort_field(:clicks, default_direction: :desc),
          LiveFilter.sort_field(:name)
        ]
      }

      html =
        rendered_to_string(~H"""
        <LiveFilter.SortComponents.sort_header field={:clicks} label="Clicks" sort={%Sort{}} sortable_fields={@sortable_fields}>
          <span class="custom-label">Hits</span>
        </LiveFilter.SortComponents.sort_header>
        """)

      assert html =~ "custom-label"
      assert html =~ "Hits"
      refute html =~ ">Clicks<"
    end
  end

  describe "sort_menu/1" do
    test "lists sortable fields as selectable rows" do
      html =
        render_component(&LiveFilter.SortComponents.sort_menu/1,
          sortable_fields: sortable(),
          sort: %Sort{}
        )

      assert html =~ "Clicks"
      assert html =~ "Name"
      assert html =~ ~s(data-field="name")
      assert html =~ ~s(data-direction)
    end

    test "inactive field rows emit the field's default direction" do
      html =
        render_component(&LiveFilter.SortComponents.sort_menu/1,
          sortable_fields: sortable(),
          sort: %Sort{}
        )

      # :clicks declares default_direction: :desc, :name defaults to :asc.
      # Menu items use the DropdownItem hook convention (data-event/data-*).
      assert html =~ ~s(data-field="clicks" data-direction="desc")
      assert html =~ ~s(data-field="name" data-direction="asc")
    end

    test "the active field row flips direction on click and shows a clear option" do
      sort = %Sort{entries: [%Entry{field: :clicks, direction: :desc}]}

      html =
        render_component(&LiveFilter.SortComponents.sort_menu/1,
          sortable_fields: sortable(),
          sort: sort,
          id: "links-sort"
        )

      # active (desc) row's click flips to asc
      assert html =~ ~s(data-field="clicks" data-direction="asc")
      # "Clear sort" clear row appears with the clear event
      assert html =~ ~s(data-event="lf_sort_clear")
      assert html =~ ~s(id="links-sort-clear")
      assert html =~ "Clear sort"
    end

    test "no clear row is shown when nothing is sorted" do
      html =
        render_component(&LiveFilter.SortComponents.sort_menu/1,
          sortable_fields: sortable(),
          sort: %Sort{}
        )

      refute html =~ "Clear sort"
    end

    test "derives hook ids from the :id attr so multiple menus stay unique" do
      html =
        render_component(&LiveFilter.SortComponents.sort_menu/1,
          sortable_fields: sortable(),
          sort: %Sort{},
          id: "links-sort"
        )

      assert html =~ ~s(id="links-sort-trigger")
      assert html =~ ~s(id="links-sort-clicks")
      assert html =~ ~s(id="links-sort-name")
      refute html =~ ~s(id="lf-sort-menu-trigger")
    end
  end
end
