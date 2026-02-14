alias Demo.Repo
alias Demo.Projects.Project
alias Demo.Assignees.Assignee
alias Demo.Tasks.Task
alias Demo.Tasks.TaskAssignee

# Clear existing data (order matters for foreign keys)
Repo.delete_all(TaskAssignee)
Repo.delete_all(Task)
Repo.delete_all(Assignee)
Repo.delete_all(Project)

# Create Projects
projects_data = [
  %{name: "Phoenix", description: "Core Phoenix framework work", color: "#FD4F00"},
  %{name: "LiveFilter", description: "LiveFilter library development", color: "#4F46E5"},
  %{name: "Dashboard", description: "Admin dashboard features", color: "#059669"},
  %{name: "API", description: "REST API development", color: "#DC2626"},
  %{name: "Docs", description: "Documentation and guides", color: "#7C3AED"}
]

projects =
  for project_data <- projects_data do
    %Project{}
    |> Project.changeset(project_data)
    |> Repo.insert!()
  end

IO.puts("Created #{length(projects)} projects")

# Create Assignees
assignees_data = [
  %{name: "Alice", email: "alice@example.com"},
  %{name: "Bob", email: "bob@example.com"},
  %{name: "Charlie", email: "charlie@example.com"},
  %{name: "Diana", email: "diana@example.com"},
  %{name: "Eve", email: "eve@example.com"},
  %{name: "Frank", email: "frank@example.com"},
  %{name: "Grace", email: "grace@example.com"}
]

assignees =
  for assignee_data <- assignees_data do
    %Assignee{}
    |> Assignee.changeset(assignee_data)
    |> Repo.insert!()
  end

IO.puts("Created #{length(assignees)} assignees")

# Task data
statuses = ~w(backlog todo in_progress review done)
all_tags = ~w(bug feature improvement docs testing security performance)

titles = [
  "Fix login redirect loop",
  "Add dark mode toggle",
  "Implement CSV export",
  "Upgrade Phoenix to 1.8",
  "Write API documentation",
  "Optimize database queries",
  "Add pagination to task list",
  "Fix date picker timezone bug",
  "Implement user notifications",
  "Add search functionality",
  "Refactor authentication module",
  "Create onboarding flow",
  "Fix mobile responsive layout",
  "Add rate limiting to API",
  "Implement file upload",
  "Write integration tests",
  "Set up CI/CD pipeline",
  "Add audit logging",
  "Fix memory leak in WebSocket",
  "Implement role-based access",
  "Create admin dashboard",
  "Add two-factor auth",
  "Optimize image loading",
  "Fix broken email templates",
  "Implement caching layer",
  "Add GraphQL endpoint",
  "Fix session timeout issue",
  "Create data export tool",
  "Implement undo/redo",
  "Add keyboard shortcuts",
  "Fix race condition in checkout",
  "Implement real-time updates",
  "Add bulk operations",
  "Fix broken pagination",
  "Implement tag system",
  "Add comment threading",
  "Fix password reset flow",
  "Create user profile page",
  "Implement drag and drop",
  "Add activity feed",
  "Fix CSS specificity issues",
  "Implement archiving",
  "Add custom fields support",
  "Fix duplicate submission bug",
  "Create reporting module",
  "Implement webhook system",
  "Add full-text search",
  "Fix timezone conversion",
  "Create changelog page",
  "Implement SSO integration",
  "Add batch import",
  "Fix N+1 query problem",
  "Create API rate dashboard",
  "Implement soft delete",
  "Add export to PDF",
  "Fix CORS configuration",
  "Create status page",
  "Implement retry logic",
  "Add custom validators",
  "Fix flaky test suite",
  "Create deployment scripts",
  "Implement feature flags",
  "Add monitoring alerts",
  "Fix date range overlap",
  "Create backup system",
  "Implement data migration",
  "Add performance benchmarks",
  "Fix broken OAuth flow",
  "Create E2E test suite",
  "Implement cron scheduler",
  "Add usage analytics",
  "Fix form validation UX",
  "Create developer docs",
  "Implement undo queue",
  "Add dark mode support",
  "Fix notification delivery",
  "Create health check endpoint",
  "Implement connection pooling",
  "Add i18n support",
  "Fix broken breadcrumbs",
  "Create seed data script",
  "Implement versioning API",
  "Add table sorting",
  "Fix Safari rendering bug",
  "Create invitation system",
  "Implement content moderation",
  "Add image cropping",
  "Fix slow query on dashboard",
  "Create plugin architecture",
  "Implement event sourcing",
  "Add auto-save draft",
  "Fix date format inconsistency",
  "Create test fixtures",
  "Implement cache invalidation",
  "Add Markdown preview",
  "Fix infinite scroll bug",
  "Create release automation",
  "Implement queue system",
  "Add custom themes",
  "Fix accessibility issues"
]

# Create tasks with random assignments
for {title, i} <- Enum.with_index(titles) do
  tags = Enum.take_random(all_tags, Enum.random(0..3))
  due_offset = Enum.random(-30..60)
  due_date = Date.add(Date.utc_today(), due_offset)
  project = Enum.random(projects)

  task =
    %Task{}
    |> Task.changeset(%{
      title: title,
      description: "Description for: #{title}",
      status: Enum.random(statuses),
      urgent: rem(i, 5) == 0,
      tags: tags,
      due_date: due_date,
      estimated_hours: Enum.random([0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 24.0, 40.0]),
      project_id: project.id
    })
    |> Repo.insert!()

  # Assign 1-3 random assignees to each task
  num_assignees = Enum.random(1..3)
  task_assignees = Enum.take_random(assignees, num_assignees)

  for assignee <- task_assignees do
    %TaskAssignee{}
    |> TaskAssignee.changeset(%{task_id: task.id, assignee_id: assignee.id})
    |> Repo.insert!()
  end
end

IO.puts("Seeded #{length(titles)} tasks with assignees")
