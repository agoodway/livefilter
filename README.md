# LiveFilter

Composable, URL-driven filtering for LiveView with Linear/Notion-style UI filters and PostgREST-compatible parameters for shareable filter states using [PgRest](https://github.com/agoodway/pgrest)

## Demo App

See [`demo/`](demo/) for an interactive filter explorer built with Phoenix LiveView.

```bash
cd demo && mix setup && mix phx.server
# Visit http://localhost:4000
```

## Prerequisites

- Elixir 1.15+
- Phoenix LiveView 1.0+
- DaisyUI (via daisy_ui_components)

## Installation

Add `live_filter` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:live_filter, "~> 0.1.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

### JavaScript Hooks

LiveFilter requires JavaScript hooks for dropdown behavior. Add them to your LiveSocket:

```javascript
import { hooks as liveFilterHooks } from "live_filter"

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { ...liveFilterHooks }
})
```

For esbuild, add the deps path to your `NODE_PATH` in `config/config.exs`:

```elixir
config :esbuild,
  version: "0.25.4",
  my_app: [
    args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" => Path.expand("../deps", __DIR__)
    }
  ]
```

## Quick Start

### 1. Define Filter Configuration

```elixir
defmodule MyAppWeb.TaskLive.Index do
  use MyAppWeb, :live_view

  defp filter_config do
    [
      LiveFilter.text(:title, label: "Search", always_on: true),
      LiveFilter.select(:status, label: "Status", options: ~w(pending active done)),
      LiveFilter.multi_select(:tags, label: "Tags", options: ~w(bug feature docs)),
      LiveFilter.boolean(:urgent, label: "Urgent Only"),
      LiveFilter.date_range(:due_date, label: "Due Date")
    ]
  end
end
```

### 2. Initialize in LiveView

```elixir
def handle_params(params, _uri, socket) do
  {filters, remaining_params} = LiveFilter.from_params(params, filter_config())

  socket =
    socket
    |> LiveFilter.init(filter_config(), filters)
    |> assign(:remaining_params, remaining_params)
    |> load_data()

  {:noreply, socket}
end

def handle_info({:live_filter, :updated, params}, socket) do
  all_params = Map.merge(socket.assigns.remaining_params, params)
  {:noreply, push_patch(socket, to: ~p"/tasks?#{all_params}")}
end
```

### 3. Render the Filter Bar (Optional)

Use the built-in UI component:

```heex
<LiveFilter.bar filter={@live_filter} />
```

Or build your own UI — the param/query layers work independently:

```elixir
# Parse params and build queries without the bar component
{filters, _} = LiveFilter.from_params(params, filter_config())
query = LiveFilter.QueryBuilder.apply(Task, filters, schema: Task, allowed_fields: [...])
```

### 4. Apply Filters to Queries

```elixir
defp load_data(socket) do
  query =
    Task
    |> LiveFilter.QueryBuilder.apply(socket.assigns.live_filter.filters,
      schema: Task,
      allowed_fields: [:title, :status, :tags, :urgent, :due_date]
    )

  assign(socket, :tasks, Repo.all(query))
end
```

## Filter Types

| Type         | Function                     | Default Operators            |
|--------------|------------------------------|------------------------------|
| Text         | `LiveFilter.text/2`          | ilike, eq, neq, like         |
| Number       | `LiveFilter.number/2`        | eq, neq, gt, gte, lt, lte    |
| Select       | `LiveFilter.select/2`        | eq, neq                      |
| Multi-select | `LiveFilter.multi_select/2`  | ov, cs                       |
| Date         | `LiveFilter.date/2`          | eq, gt, gte, lt, lte         |
| Date Range   | `LiveFilter.date_range/2`    | gte_lte                      |
| DateTime     | `LiveFilter.datetime/2`      | eq, gt, gte, lt, lte         |
| Boolean      | `LiveFilter.boolean/2`       | is                           |
| Radio Group  | `LiveFilter.radio_group/2`   | eq                           |

## Display Modes

LiveFilter supports two display modes for filter chips:

| Mode       | Description                                                    |
|------------|----------------------------------------------------------------|
| `:basic`   | Simple chips without operator selection (default)              |
| `:command` | Full chips with inline operator dropdown (Linear/Notion style) |

Set the mode globally on the bar:

```heex
<LiveFilter.bar filter={@live_filter} mode={:command} />
```

Or per-filter in the configuration:

```elixir
LiveFilter.number(:estimated_hours, label: "Hours", mode: :command)
```

## Filter Options

```elixir
LiveFilter.text(:field,
  label: "Display Label",        # Human-readable label
  always_on: true,               # Always visible (not removable)
  operators: [:eq, :ilike],      # Allowed operators
  default_operator: :ilike,      # Default when adding filter
  placeholder: "Search...",      # Input placeholder
  custom_param: "search",        # Custom URL param name
  query_field: :other_field,     # Query different DB column
  mode: :command                 # Display mode for this filter
)

LiveFilter.select(:status,
  options: ["pending", "active"],           # Static options
  options_fn: fn -> fetch_options() end     # Dynamic options
)

LiveFilter.boolean(:active,
  nullable: true,                # Allow nil (Any) state
  true_label: "Active",          # Custom label for true
  false_label: "Inactive",       # Custom label for false
  any_label: "All"               # Custom label for nil
)
```

## License

MIT
