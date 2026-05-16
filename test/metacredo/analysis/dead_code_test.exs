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
