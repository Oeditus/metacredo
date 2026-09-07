defmodule MetaCredo.Check.Readability.ModuleDoc do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    param_defaults: [check_exs: false],
    explanations: [
      check: """
      Detects modules without documentation. Every module should have
      a `@moduledoc` describing its purpose.
      """,
      params: [
        check_exs: "Check moduledoc in .exs script/config files (default: false)"
      ],
      examples: [
        elixir: [
          wrong: """
          # No documentation -- purpose is unknown to new readers
          defmodule MyApp.Accounts.UserToken do
            use Ecto.Schema
            import Ecto.Changeset

            schema "user_tokens" do
              ...
            end
          end
          """,
          correct: """
          defmodule MyApp.Accounts.UserToken do
            @moduledoc \"\"\"
            Manages authentication tokens for users.

            Tokens are single-use, time-limited, and scoped to a specific
            context (e.g. password reset or email confirmation).
            \"\"\"

            use Ecto.Schema
            import Ecto.Changeset

            schema "user_tokens" do
              ...
            end
          end
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    check_exs = params_get(params, :check_exs)

    if not check_exs and String.ends_with?(source_file.filename, ".exs") do
      []
    else
      {_, issues} =
        source_file
        |> SourceFile.ast()
        |> AST.prewalk([], fn node, acc ->
          traverse(node, acc, source_file)
        end)

      issues
    end
  end

  defp traverse({:container, meta, children} = node, issues, source_file)
       when is_list(meta) and is_list(children) do
    name = Keyword.get(meta, :name, "unknown")

    if has_doc_comment?(children) do
      {node, issues}
    else
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Module '#{name}' has no documentation",
          trigger: to_string(name),
          line_no: line
        )

      {node, [issue | issues]}
    end
  end

  defp traverse(node, issues, _sf), do: {node, issues}

  defp has_doc_comment?(children) when is_list(children) do
    Enum.any?(children, &is_doc_node?/1)
  end

  defp is_doc_node?({:assignment, meta, [{:variable, _, var_name} | _]}) when is_list(meta) do
    var_name in ["@moduledoc", ":moduledoc", "moduledoc"] or
      (Keyword.get(meta, :attribute_type) == :module_attribute and var_name in ["@moduledoc", "moduledoc"])
  end

  defp is_doc_node?({:attribute, meta, [attr_name | _]}) when is_list(meta) do
    to_string(attr_name) in ["@moduledoc", "moduledoc", ":moduledoc"]
  end

  defp is_doc_node?({:comment, meta, _text}) when is_list(meta) do
    Keyword.get(meta, :comment_kind) == :doc or Keyword.get(meta, :doc) == true
  end

  defp is_doc_node?({:block, _meta, statements}) when is_list(statements) do
    Enum.any?(statements, &is_doc_node?/1)
  end

  defp is_doc_node?(_node), do: false
end
