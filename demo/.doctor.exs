%Doctor.Config{
  ignore_modules: [
    Demo.Assignees.Assignee,
    Demo.Projects.Project,
    Demo.Release,
    Demo.Repo,
    Demo.Tasks.Task,
    Demo.Tasks.TaskAssignee,
    DemoWeb,
    DemoWeb.Endpoint,
    DemoWeb.ErrorHTML,
    DemoWeb.ErrorJSON,
    DemoWeb.PageController,
    DemoWeb.Router,
    DemoWeb.Telemetry,
    DemoWeb.TaskLive.Index
  ],
  ignore_paths: [~r"^test/"],
  min_module_doc_coverage: 40,
  min_module_spec_coverage: 0,
  min_overall_doc_coverage: 50,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 0,
  exception_moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false
}
