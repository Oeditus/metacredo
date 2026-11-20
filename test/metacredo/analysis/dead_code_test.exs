defmodule MetaCredo.Analysis.DeadCodeTest do
  use ExUnit.Case, async: true

  alias MetaCredo.Analysis.DeadCode
  alias Metastatic.Document

  describe "analyze/1" do
    test "no dead code in simple expression" do
      ast =
        {:binary_op, [category: :arithmetic, operator: :+],
         [
           {:literal, [subtype: :integer], 1},
           {:literal, [subtype: :integer], 2}
         ]}

      doc = Document.new(ast, :elixir)

      assert {:ok, result} = DeadCode.analyze(doc)
      refute result.has_dead_code?
    end

    test "detects unreachable code after return" do
      ast =
        {:block, [],
         [
           {:early_return, [], [{:literal, [subtype: :integer], 1}]},
           {:literal, [subtype: :integer], 2}
         ]}

      doc = Document.new(ast, :python)

      assert {:ok, result} = DeadCode.analyze(doc)
      assert result.has_dead_code?
      assert result.total_dead_statements >= 1
      assert [location | _] = result.dead_locations
      assert location.type == :unreachable_after_return
    end

    test "detects constant conditional (always true)" do
      ast =
        {:conditional, [],
         [
           {:literal, [subtype: :boolean], true},
           {:literal, [subtype: :integer], 1},
           {:literal, [subtype: :integer], 2}
         ]}

      doc = Document.new(ast, :elixir)

      assert {:ok, result} = DeadCode.analyze(doc)
      assert result.has_dead_code?
      assert Enum.any?(result.dead_locations, &(&1.type == :constant_conditional))
    end

    # `raise`/`throw`/`return` arrive as plain `:function_call` nodes, not as
    # `:early_return`. Only matching `:early_return` missed every one of them.
    test "detects unreachable code after raise/throw/exit/return" do
      for terminator <- ~w(raise throw exit return) do
        ast =
          {:block, [],
           [
             {:function_call, [name: terminator], [{:literal, [subtype: :string], "stop"}]},
             {:function_call, [name: "Logger.info"], [{:literal, [subtype: :string], "after"}]}
           ]}

        assert {:ok, result} = DeadCode.analyze(Document.new(ast, :elixir))

        assert result.has_dead_code?,
               "code after #{terminator} was not reported as unreachable"

        assert result.total_dead_statements == 1
      end
    end

    test "a non-terminating call does not make following code unreachable" do
      ast =
        {:block, [],
         [
           {:function_call, [name: "Logger.info"], [{:literal, [subtype: :string], "a"}]},
           {:function_call, [name: "Logger.info"], [{:literal, [subtype: :string], "b"}]}
         ]}

      assert {:ok, result} = DeadCode.analyze(Document.new(ast, :elixir))
      refute result.has_dead_code?
    end
  end

  describe "analyze!/1" do
    test "returns result directly" do
      ast = {:literal, [subtype: :integer], 42}
      doc = Document.new(ast, :elixir)

      result = DeadCode.analyze!(doc)
      refute result.has_dead_code?
    end
  end
end
