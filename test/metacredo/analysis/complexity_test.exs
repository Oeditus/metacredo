defmodule MetaCredo.Analysis.ComplexityTest do
  use ExUnit.Case, async: true

  alias MetaCredo.Analysis.Complexity
  alias Metastatic.Document

  describe "analyze/1" do
    test "returns complexity metrics for a simple literal" do
      ast = {:literal, [subtype: :integer], 42}
      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Complexity.analyze(doc)
      assert result.cyclomatic == 1
      assert result.cognitive == 0
    end

    test "detects cyclomatic complexity from conditionals" do
      ast =
        {:conditional, [],
         [
           {:variable, [], "x"},
           {:literal, [subtype: :integer], 1},
           {:literal, [subtype: :integer], 2}
         ]}

      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Complexity.analyze(doc)
      assert result.cyclomatic == 2
    end
  end

  describe "analyze/2 with options" do
    test "accepts specific metrics" do
      ast = {:literal, [subtype: :integer], 42}
      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Complexity.analyze(doc, metrics: [:cyclomatic])
      assert result.cyclomatic == 1
    end
  end

  describe "analyze!/1" do
    test "returns result directly" do
      ast = {:literal, [subtype: :integer], 42}
      doc = Document.new(ast, :elixir)

      result = Complexity.analyze!(doc)
      assert result.cyclomatic == 1
    end
  end

  describe "delegation identity" do
    test "returns identical results to Metastatic.Analysis.Complexity" do
      ast =
        {:conditional, [],
         [
           {:variable, [], "x"},
           {:literal, [subtype: :integer], 1},
           {:literal, [subtype: :integer], 2}
         ]}

      doc = Document.new(ast, :elixir)

      {:ok, meta_result} = Metastatic.Analysis.Complexity.analyze(doc)
      {:ok, mc_result} = Complexity.analyze(doc)

      assert meta_result.cyclomatic == mc_result.cyclomatic
      assert meta_result.cognitive == mc_result.cognitive
      assert meta_result.max_nesting == mc_result.max_nesting
    end
  end
end
