defmodule DemoWeb.TaskLive.Index do
  use DemoWeb, :live_view

  alias Demo.{Projects, Repo, Tasks}
  alias Demo.Tasks.Task
  alias LiveFilter.{Pagination, Params.Serializer, QueryBuilder, Sort}

  defp sortable_fields do
    [
      LiveFilter.sort_field(:title, label: "Title"),
      LiveFilter.sort_field(:status, label: "Status"),
      LiveFilter.sort_field(:estimated_hours,
        label: "Hours",
        default_direction: :desc,
        nulls: :last
      ),
      LiveFilter.sort_field(:due_date,
        label: "Due",
        default_direction: :desc,
        nulls: :last
      )
    ]
  end

  defp default_sort, do: %Sort{}

  # Showcases the breadth of LiveFilter field types against the Task schema:
  # text (ilike), select (command-mode, multi), async_select (search-as-you-type),
  # boolean, number (comparison operators), date_range, datetime_range, and
  # multi_select (array containment).
  defp filter_config do
    [
      LiveFilter.text(:title,
        label: "Search",
        always_on: true,
        custom_param: "search",
        hide_label: true
      ),
      LiveFilter.select(:status,
        label: "Status",
        options: [
          {"Backlog", "backlog"},
          {"Todo", "todo"},
          {"In Progress", "in_progress"},
          {"Review", "review"},
          {"Done", "done"}
        ],
        icon: "hero-signal",
        default_visible: true,
        operators: [:eq, :neq, :in, :not_in],
        mode: :command
      ),
      LiveFilter.async_select(:project_id,
        label: "Project",
        icon: "hero-folder",
        placeholder: "Search projects…",
        search_fn: &search_projects/2,
        load_label_fn: &project_label/2
      ),
      LiveFilter.boolean(:urgent, label: "Urgent", icon: "hero-exclamation-triangle"),
      # Comparison filter: the number type exposes eq/neq plus the
      # greater/less-than operators (gt, gte, lt, lte).
      LiveFilter.number(:estimated_hours,
        label: "Est. Hours",
        icon: "hero-clock",
        operators: [:eq, :neq, :gt, :gte, :lt, :lte],
        default_operator: :gte,
        default_visible: true,
        mode: :command
      ),
      LiveFilter.date_range(:due_date,
        label: "Due Date",
        icon: "hero-calendar-days",
        default_visible: true
      ),
      LiveFilter.datetime_range(:inserted_at,
        label: "Created",
        icon: "hero-clock"
      ),
      LiveFilter.multi_select(:tags,
        label: "Tags",
        options: ~w(bug feature improvement docs testing security performance),
        search_threshold: 5,
        icon: "hero-tag",
        default_visible: true
      )
    ]
  end

  # async_select callbacks: filter the in-memory project list by the typed query
  # and resolve a stored project_id back to its display label on URL reload.
  defp search_projects(query, _context) do
    normalized = String.downcase(query)

    Projects.list_projects()
    |> Enum.filter(&String.contains?(String.downcase(&1.name), normalized))
    |> Enum.map(&{to_string(&1.id), &1.name})
  end

  defp project_label(value, _context) do
    case Enum.find(Projects.list_projects(), &(to_string(&1.id) == to_string(value))) do
      nil -> :error
      project -> {:ok, project.name}
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Tasks")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {filters, remaining} = LiveFilter.from_params(params, filter_config())
    {pagination, remaining} = LiveFilter.pagination_from_params(remaining, default_limit: 25)

    {sort, remaining} =
      LiveFilter.sort_from_params(remaining, sortable_fields(), default: default_sort())

    socket =
      socket
      |> LiveFilter.init(filter_config(), filters)
      |> assign(:pagination, pagination)
      |> assign(:sort, sort)
      |> assign(:remaining_params, remaining)
      |> load_tasks()

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:livefilter, :updated, params},
        %{assigns: %{remaining_params: remaining_params, pagination: %{limit: limit}, sort: sort}} =
          socket
      ) do
    pagination_params = %{"limit" => to_string(limit), "offset" => "0"}

    all_params =
      remaining_params
      |> Map.merge(params)
      |> Map.merge(Sort.to_params(sort))
      |> Map.merge(pagination_params)

    {:noreply, push_patch(socket, to: LiveFilter.to_path("/tasks", all_params))}
  end

  def handle_info(
        {:livefilter, :page_changed, pagination_params},
        %{
          assigns: %{
            remaining_params: remaining_params,
            livefilter: %{filters: filters},
            sort: sort
          }
        } = socket
      ) do
    filter_params = Serializer.to_params(filters)

    all_params =
      remaining_params
      |> Map.merge(filter_params)
      |> Map.merge(Sort.to_params(sort))
      |> Map.merge(pagination_params)

    {:noreply, push_patch(socket, to: LiveFilter.to_path("/tasks", all_params))}
  end

  @impl true
  def handle_event("lf_sort", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)
    sort = Sort.toggle(socket.assigns.sort, field, sortable_fields())
    {:noreply, push_patch(socket, to: sort_path(socket, sort))}
  end

  defp sort_path(socket, sort) do
    filter_params = Serializer.to_params(socket.assigns.livefilter.filters)
    pagination_params = %{"limit" => to_string(socket.assigns.pagination.limit), "offset" => "0"}

    all_params =
      socket.assigns.remaining_params
      |> Map.merge(filter_params)
      |> Map.merge(Sort.to_params(sort))
      |> Map.merge(pagination_params)

    LiveFilter.to_path("/tasks", all_params)
  end

  defp load_tasks(
         %{assigns: %{pagination: pagination, sort: sort, livefilter: %{filters: filters}}} =
           socket
       ) do
    base_query =
      Task
      |> QueryBuilder.apply(filters,
        schema: Task,
        allowed_fields: [
          :title,
          :status,
          :project_id,
          :urgent,
          :due_date,
          :inserted_at,
          :tags,
          :estimated_hours
        ]
      )

    total_count = QueryBuilder.count(base_query, Repo)

    tasks =
      base_query
      |> QueryBuilder.apply_sort(sort)
      |> QueryBuilder.apply_pagination(pagination)
      |> Tasks.list_tasks()

    pagination = Pagination.with_total(pagination, total_count)

    socket
    |> assign(:tasks, tasks)
    |> assign(:pagination, pagination)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <div class="text-center max-w-4xl lg:max-w-5xl xl:max-w-6xl 2xl:max-w-7xl mx-auto mb-4">
          <p class="text-base-content/70 text-sm leading-relaxed">
            Composable, URL-driven filtering for LiveView with Linear/Notion-style UI filters and PostgREST-compatible parameters for shareable filter states using <a
              href="https://github.com/agoodway/pgrest"
              target="_blank"
              class="font-medium text-primary hover:underline"
            >PgRest</a>.
          </p>
        </div>

        <div class="lf-filter-section">
          <LiveFilter.bar filter={@livefilter} />
        </div>

        <div class="bg-base-100 rounded-xl border border-base-200 overflow-hidden shadow-sm">
          <.table id="tasks" rows={@tasks} row_id={fn task -> "task-#{task.id}" end}>
            <:header>
              <LiveFilter.sort_header
                field={:title}
                label="Title"
                sort={@sort}
                sortable_fields={sortable_fields()}
              />
            </:header>
            <:header>Project</:header>
            <:header>
              <LiveFilter.sort_header
                field={:status}
                label="Status"
                sort={@sort}
                sortable_fields={sortable_fields()}
              />
            </:header>
            <:header>Assignees</:header>
            <:header>Tags</:header>
            <:header>
              <LiveFilter.sort_header
                field={:estimated_hours}
                label="Hours"
                sort={@sort}
                sortable_fields={sortable_fields()}
              />
            </:header>
            <:header>
              <LiveFilter.sort_header
                field={:due_date}
                label="Due"
                sort={@sort}
                sortable_fields={sortable_fields()}
              />
            </:header>
            <:col :let={task} label="Title">
              <div class="flex items-center gap-2">
                <span :if={task.urgent} class="urgent-indicator" title="Urgent">
                  <span class="hero-exclamation-triangle-mini size-4" />
                </span>
                <span class="font-medium text-base-content">{task.title}</span>
              </div>
            </:col>
            <:col :let={task} label="Project">
              <.project_badge project={task.project} />
            </:col>
            <:col :let={task} label="Status">
              <.status_pill status={task.status} />
            </:col>
            <:col :let={task} label="Assignees">
              <.assignee_avatars assignees={task.assignees} />
            </:col>
            <:col :let={task} label="Tags">
              <div class="flex flex-wrap gap-1">
                <span :for={tag <- task.tags || []} class="tag-chip">{tag}</span>
              </div>
            </:col>
            <:col :let={task} label="Hours">
              <span class="tabular-nums text-base-content/70 text-right block">
                {if task.estimated_hours,
                  do: :erlang.float_to_binary(task.estimated_hours / 1, decimals: 1),
                  else: "—"}
              </span>
            </:col>
            <:col :let={task} label="Due">
              <span class="text-base-content/70 tabular-nums">
                {if task.due_date, do: Calendar.strftime(task.due_date, "%b %d, %Y"), else: "—"}
              </span>
            </:col>
          </.table>
        </div>

        <LiveFilter.paginator pagination={@pagination} />
      </div>
    </Layouts.app>
    """
  end

  defp project_badge(assigns) do
    ~H"""
    <span
      :if={@project}
      class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-md text-xs font-medium"
      style={"background-color: #{@project.color}20; color: #{@project.color}; border: 1px solid #{@project.color}40;"}
    >
      <span class="size-2 rounded-full" style={"background-color: #{@project.color};"} />
      {@project.name}
    </span>
    """
  end

  defp status_pill(assigns) do
    {icon, label} =
      case assigns.status do
        "done" -> {"hero-check-mini", "Done"}
        "in_progress" -> {"hero-play-mini", "In Progress"}
        "review" -> {"hero-eye-mini", "Review"}
        "todo" -> {"hero-check-circle-mini", "Todo"}
        "backlog" -> {"hero-queue-list-mini", "Backlog"}
        _ -> {"hero-question-mark-circle-mini", assigns.status}
      end

    assigns = assign(assigns, icon: icon, label: label)

    ~H"""
    <span class={"status-pill status-pill--#{@status}"}>
      <span class={[@icon, "size-3.5"]} />
      {@label}
    </span>
    """
  end

  defp assignee_avatars(assigns) do
    ~H"""
    <div class="flex -space-x-2">
      <div
        :for={assignee <- Enum.take(@assignees, 3)}
        class="size-7 rounded-full bg-primary/10 border-2 border-base-100 flex items-center justify-center text-xs font-medium text-primary"
        title={assignee.name}
      >
        {String.first(assignee.name)}
      </div>
      <div
        :if={length(@assignees) > 3}
        class="size-7 rounded-full bg-base-200 border-2 border-base-100 flex items-center justify-center text-xs font-medium text-base-content/70"
      >
        +{length(@assignees) - 3}
      </div>
    </div>
    """
  end
end
