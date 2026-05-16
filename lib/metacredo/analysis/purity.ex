defmodule MetaCredo.Analysis.Purity do
  @moduledoc """
  Programmatic purity / side-effect analysis API.

  Determines whether code is pure (no side effects) or impure
  (I/O, mutations, random operations, etc.) by operating on
  the unified MetaAST representation.

  ## Usage

      alias Metastatic.Document
      alias MetaCredo.Analysis.Purity

      doc = Document.new(ast, :elixir)
      {:ok, result} = Purity.analyze(doc)

      result.pure?        # => true
      result.effects      # => []
      result.confidence   # => :high
  """

  alias MetaCredo.Analysis.Purity.{Effects, Result}
  alias Metastatic.Document

  use MetaCredo.Analysis.Analyzer,
    doc: """
    Analyzes a document for purity.

    Returns `{:ok, result}` where result is a `MetaCredo.Analysis.Purity.Result` struct.
    """

  @impl MetaCredo.Analysis.Analyzer
  def handle_analyze(%Document{ast: ast}, _opts \\ []) do
    result =
      ast
      |> walk(%{in_loop: false, effects: [], locations: [], unknown: []})
      |> build_result()

    {:ok, result}
  end

  defp walk(ast, ctx) do
    effects = Effects.detect(ast)
    ctx = add_effects(ctx, effects)
    walk_node(ast, ctx)
  end

  defp walk_node({:binary_op, _meta, [left, right]}, ctx) do
    ctx = walk(left, ctx)
    walk(right, ctx)
  end

  defp walk_node({:unary_op, _meta, [operand]}, ctx), do: walk(operand, ctx)

  defp walk_node({:conditional, _meta, [cond_expr, then_br, else_br]}, ctx) do
    ctx = walk(cond_expr, ctx)
    ctx = walk(then_br, ctx)
    walk(else_br, ctx)
  end

  defp walk_node({:block, _meta, stmts}, ctx) when is_list(stmts) do
    Enum.reduce(stmts, ctx, fn stmt, c -> walk(stmt, c) end)
  end

  defp walk_node({:loop, meta, children}, ctx) when is_list(meta) do
    loop_type = Keyword.get(meta, :loop_type)
    loop_ctx = %{ctx | in_loop: true}

    case {loop_type, children} do
      {:while, [cond_expr, body]} ->
        loop_ctx = walk(cond_expr, loop_ctx)
        walk(body, loop_ctx)

      {_, [iter, coll, body]} ->
        loop_ctx = walk(iter, loop_ctx)
        loop_ctx = walk(coll, loop_ctx)
        walk(body, loop_ctx)

      _ ->
        Enum.reduce(children, loop_ctx, fn child, c -> walk(child, c) end)
    end
  end

  defp walk_node({:assignment, _meta, [target, value]}, ctx) do
    ctx = if ctx.in_loop, do: add_effects(ctx, [:mutation]), else: ctx
    ctx = walk(target, ctx)
    walk(value, ctx)
  end

  defp walk_node({:inline_match, _meta, [pattern, value]}, ctx) do
    ctx = walk(pattern, ctx)
    walk(value, ctx)
  end

  defp walk_node({:function_call, meta, args}, ctx) when is_list(meta) and is_list(args) do
    name = Keyword.get(meta, :name)

    ctx =
      if Effects.detect({:function_call, meta, args}) == [] and is_binary(name) do
        %{ctx | unknown: [name | ctx.unknown]}
      else
        ctx
      end

    Enum.reduce(args, ctx, fn arg, c -> walk(arg, c) end)
  end

  defp walk_node({:lambda, _meta, [body]}, ctx), do: walk(body, ctx)

  defp walk_node({:collection_op, _meta, children}, ctx) when is_list(children) do
    Enum.reduce(children, ctx, fn child, c -> walk(child, c) end)
  end

  defp walk_node({:exception_handling, _meta, [try_b, catches, else_b]}, ctx) do
    ctx = walk(try_b, ctx)
    catches_list = if is_list(catches), do: catches, else: []
    ctx = Enum.reduce(catches_list, ctx, fn catch_clause, c -> walk(catch_clause, c) end)
    walk(else_b, ctx)
  end

  defp walk_node({:early_return, _meta, [value]}, ctx), do: walk(value, ctx)

  defp walk_node({:list, _meta, elems}, ctx) when is_list(elems) do
    Enum.reduce(elems, ctx, fn elem, c -> walk(elem, c) end)
  end

  defp walk_node({:map, _meta, pairs}, ctx) when is_list(pairs) do
    Enum.reduce(pairs, ctx, fn
      {:pair, _, [key, value]}, c ->
        c = walk(key, c)
        walk(value, c)

      {key, value}, c ->
        c = walk(key, c)
        walk(value, c)

      other, c ->
        walk(other, c)
    end)
  end

  defp walk_node({:language_specific, _meta, _native_ast}, ctx), do: ctx
  defp walk_node({:literal, _meta, _value}, ctx), do: ctx
  defp walk_node({:variable, _meta, _name}, ctx), do: ctx

  defp walk_node({:pair, _meta, [key, value]}, ctx) do
    ctx = walk(key, ctx)
    walk(value, ctx)
  end

  defp walk_node(_, ctx), do: ctx

  defp add_effects(ctx, []), do: ctx
  defp add_effects(ctx, effects), do: %{ctx | effects: ctx.effects ++ effects}

  defp build_result(%{effects: [], unknown: []}), do: Result.pure()

  defp build_result(%{effects: [], unknown: unknown}) when unknown != [],
    do: Result.unknown(Enum.uniq(unknown))

  defp build_result(%{effects: effects, locations: _}), do: Result.impure(Enum.uniq(effects), [])
end
