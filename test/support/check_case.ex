defmodule MetaCredo.CheckCase do
  @moduledoc """
  Test helpers for MetaCredo check tests.

  Provides conveniences for building `SourceFile` fixtures from raw MetaAST,
  running checks, and asserting on issues.

  ## Usage

      use MetaCredo.CheckCase

      test "detects issue" do
        issues = run_check(MyCheck, ast: some_ast)
        assert_issue(issues, message: ~r/some pattern/)
      end
  """

  use ExUnit.CaseTemplate

  alias MetaCredo.{Issue, SourceFile}
  alias Metastatic.Document

  using do
    quote do
      import MetaCredo.CheckCase
      alias MetaCredo.{Issue, SourceFile}
      alias Metastatic.AST
    end
  end

  @doc """
  Builds a `SourceFile` from raw MetaAST.

  ## Options

  - `:language` - Source language (default: `:elixir`)
  - `:filename` - Filename (default: `"test.ex"`)
  - `:source` - Original source text (default: `""`)
  """
  def source_file_from_ast(ast, opts \\ []) do
    language = Keyword.get(opts, :language, :elixir)
    filename = Keyword.get(opts, :filename, "test.ex")
    source = Keyword.get(opts, :source, "")

    doc = Document.new(ast, language)

    lines =
      source |> String.split("\n") |> Enum.with_index(1) |> Enum.map(fn {l, i} -> {i, l} end)

    %SourceFile{
      document: doc,
      filename: filename,
      source: source,
      language: language,
      lines: lines,
      status: :valid
    }
  end

  @doc """
  Runs a check on a MetaAST and returns issues.

  ## Options

  - `:ast` (required) - The MetaAST to analyze
  - `:params` - Check params (default: `[]`)
  - `:language` - Language (default: `:elixir`)
  - `:filename` - Filename (default: `"test.ex"`)
  - `:source` - Source text (default: `""`)
  """
  def run_check(check_module, opts) do
    ast = Keyword.fetch!(opts, :ast)
    params = Keyword.get(opts, :params, [])
    sf = source_file_from_ast(ast, opts)
    check_module.run(sf, params)
  end

  @doc """
  Asserts that at least one issue matches the given criteria.

  ## Criteria

  - `:message` - String or Regex to match against message
  - `:category` - Expected category atom
  - `:severity` - Expected severity atom
  - `:line_no` - Expected line number
  - `:trigger` - Expected trigger string
  - `:check` - Expected check module
  """
  def assert_issue(issues, criteria) when is_list(criteria) do
    match =
      Enum.find(issues, fn issue ->
        Enum.all?(criteria, fn {key, expected} ->
          actual = Map.get(issue, key)
          matches_criterion?(actual, expected)
        end)
      end)

    if is_nil(match) do
      flunk("""
      Expected to find an issue matching:
        #{inspect(criteria)}

      Got #{length(issues)} issue(s):
        #{Enum.map_join(issues, "\n  ", &inspect_issue/1)}
      """)
    end

    match
  end

  @doc "Asserts no issues were found."
  def assert_no_issues(issues) do
    if issues != [] do
      flunk("""
      Expected no issues, but found #{length(issues)}:
        #{Enum.map_join(issues, "\n  ", &inspect_issue/1)}
      """)
    end
  end

  @doc "Asserts exactly `n` issues were found."
  def assert_issue_count(issues, n) do
    actual = length(issues)

    if actual != n do
      flunk("""
      Expected #{n} issue(s), but found #{actual}:
        #{Enum.map_join(issues, "\n  ", &inspect_issue/1)}
      """)
    end
  end

  @doc "Asserts all issues belong to the given category."
  def assert_all_category(issues, category) do
    bad = Enum.reject(issues, &(&1.category == category))

    if bad != [] do
      flunk(
        "Expected all issues in category #{inspect(category)}, but found: #{inspect(Enum.map(bad, & &1.category))}"
      )
    end
  end

  # -- Private --

  defp matches_criterion?(actual, %Regex{} = regex), do: Regex.match?(regex, to_string(actual))
  defp matches_criterion?(actual, expected), do: actual == expected

  defp inspect_issue(%Issue{} = i) do
    "[#{i.category}] #{i.message} (line: #{i.line_no}, trigger: #{i.trigger})"
  end

  # -- AST Builder Helpers --

  @doc "Builds a literal string node."
  def literal_string(value, meta_extra \\ []) do
    {:literal, [subtype: :string] ++ meta_extra, value}
  end

  @doc "Builds a literal integer node."
  def literal_int(value, meta_extra \\ []) do
    {:literal, [subtype: :integer] ++ meta_extra, value}
  end

  @doc "Builds a literal symbol/atom node."
  def literal_symbol(value, meta_extra \\ []) do
    {:literal, [subtype: :symbol] ++ meta_extra, value}
  end

  @doc "Builds a variable node."
  def var(name, meta_extra \\ []) do
    {:variable, meta_extra, name}
  end

  @doc "Builds a function call node."
  def call(name, args, meta_extra \\ []) do
    {:function_call, [name: name] ++ meta_extra, args}
  end

  @doc "Builds a binary operation node."
  def binop(category, operator, left, right, meta_extra \\ []) do
    {:binary_op, [category: category, operator: operator] ++ meta_extra, [left, right]}
  end

  @doc "Builds an assignment node."
  def assign(target, value, meta_extra \\ []) do
    {:assignment, meta_extra, [target, value]}
  end

  @doc "Builds a block node."
  def block(statements, meta_extra \\ []) do
    {:block, meta_extra, statements}
  end

  @doc "Builds a tuple node."
  def tuple(elements, meta_extra \\ []) do
    {:tuple, meta_extra, elements}
  end

  @doc "Builds a function_def node."
  def function_def(name, params, body, meta_extra \\ []) do
    param_nodes = Enum.map(params, fn p -> {:param, [], p} end)
    {:function_def, [name: name, params: param_nodes] ++ meta_extra, body}
  end

  @doc "Builds a container (module) node."
  def container(type, name, body, meta_extra \\ []) do
    {:container, [container_type: type, name: name] ++ meta_extra, body}
  end

  @doc "Builds a conditional node."
  def conditional(condition, then_branch, else_branch, meta_extra \\ []) do
    {:conditional, meta_extra, [condition, then_branch, else_branch]}
  end

  @doc "Builds an exception_handling node."
  def exception_handling(try_block, handlers, finally \\ nil, meta_extra \\ []) do
    {:exception_handling, meta_extra, [try_block, handlers, finally]}
  end

  @doc "Builds a pattern_match (case) node."
  def pattern_match(scrutinee, arms, meta_extra \\ []) do
    {:pattern_match, meta_extra, [scrutinee | arms]}
  end

  @doc "Builds a match_arm node."
  def match_arm(pattern, body, meta_extra \\ []) do
    {:match_arm, [pattern: pattern] ++ meta_extra, body}
  end

  @doc "Builds an import node."
  def import_node(source, meta_extra \\ []) do
    {:import, [source: source] ++ meta_extra, []}
  end

  @doc "Builds a comment node."
  def comment(text, meta_extra \\ []) do
    {:comment, [comment_kind: :line] ++ meta_extra, text}
  end

  @doc "Builds a module-attribute assignment node (e.g. @moduledoc, @doc)."
  def doc_attr(attr_name, content, meta_extra \\ []) do
    {:assignment, [attribute_type: :module_attribute] ++ meta_extra,
     [
       {:variable, [scope: :module_attribute], "@#{attr_name}"},
       {:literal, [subtype: :string], content}
     ]}
  end

  @doc "Builds a doc attribute with string interpolation (simulates heredoc with \#{})."
  def doc_attr_interpolated(attr_name, string_parts, meta_extra \\ []) do
    parts =
      Enum.map(string_parts, fn
        part when is_binary(part) -> {:literal, [subtype: :string], part}
        other -> other
      end)

    {:assignment, [attribute_type: :module_attribute] ++ meta_extra,
     [
       {:variable, [scope: :module_attribute], "@#{attr_name}"},
       {:string_interpolation, [], parts}
     ]}
  end
end
