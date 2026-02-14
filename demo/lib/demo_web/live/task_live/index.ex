defmodule DemoWeb.TaskLive.Index do
  use DemoWeb, :live_view

  alias Demo.Tasks
  alias Demo.Tasks.Task
  alias Demo.Projects

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
        default_visible: true
      ),
      LiveFilter.select(:project_id,
        label: "Project",
        options_fn: fn -> Projects.project_options() end,
        icon: "hero-folder"
      ),
      LiveFilter.boolean(:urgent, label: "Urgent", icon: "hero-exclamation-triangle"),
      LiveFilter.date_range(:due_date, label: "Due Date", icon: "hero-calendar-days", default_visible: true),
      LiveFilter.multi_select(:tags,
        label: "Tags",
        options: ~w(bug feature improvement docs testing security performance),
        search_threshold: 5,
        icon: "hero-tag",
        default_visible: true
      ),
      LiveFilter.number(:estimated_hours, label: "Est. Hours", icon: "hero-clock", mode: :command)
    ]
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Tasks")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {filters, remaining} = LiveFilter.from_params(params, filter_config())

    socket =
      socket
      |> LiveFilter.init(filter_config(), filters)
      |> assign(:remaining_params, remaining)
      |> load_tasks()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:live_filter, :updated, params}, socket) do
    all_params = Map.merge(socket.assigns.remaining_params, params)
    {:noreply, push_patch(socket, to: LiveFilter.to_path("/tasks", all_params))}
  end

  defp load_tasks(socket) do
    query =
      Task
      |> LiveFilter.QueryBuilder.apply(socket.assigns.live_filter.filters,
        schema: Task,
        allowed_fields: [
          :title,
          :status,
          :project_id,
          :urgent,
          :due_date,
          :tags,
          :estimated_hours
        ]
      )

    assign(socket, :tasks, Tasks.list_tasks(query))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <div class="lf-filter-section">
          <LiveFilter.bar filter={@live_filter} />
        </div>

        <div class="bg-base-100 rounded-xl border border-base-200 overflow-hidden shadow-sm">
          <.table id="tasks" rows={@tasks} row_id={fn task -> "task-#{task.id}" end}>
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
                {if task.estimated_hours, do: :erlang.float_to_binary(task.estimated_hours / 1, decimals: 1), else: "—"}
              </span>
            </:col>
            <:col :let={task} label="Due">
              <span class="text-base-content/70 tabular-nums">
                {if task.due_date, do: Calendar.strftime(task.due_date, "%b %d, %Y"), else: "—"}
              </span>
            </:col>
          </.table>
        </div>
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
