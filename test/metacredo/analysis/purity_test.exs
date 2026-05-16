defmodule MetaCredo.Analysis.PurityTest do
  use ExUnit.Case, async: true

  alias MetaCredo.Analysis.Purity
  alias Metastatic.Document

  describe "analyze/1" do
    test "pure arithmetic is detected as pure" do
      ast =
        {:binary_op, [category: :arithmetic, operator: :+],
         [
           {:literal, [subtype: :integer], 1},
           {:literal, [subtype: :integer], 2}
         ]}

      doc = Document.new(ast, :elixir)

      assert {:ok, result} = Purity.analyze(doc)
      assert result.pure?
      assert result.effects == []
    end

    test "I/O call is detected as impure" do
      ast = {:function_call, [name: "print"], [{:literal, [subtype: :string], "hello"}]}
      doc = Document.new(ast, :python)

      assert {:ok, result} = Purity.analyze(doc)
      refute result.pure?
      assert :io in result.effects
    end
  end

  describe "analyze!/1" do
    test "returns result directly for pure code" do
      ast = {:literal, [subtype: :integer], 42}
      doc = Document.new(ast, :elixir)

      result = Purity.analyze!(doc)
      assert result.pure?
    end
  end

  describe "delegation identity" do
    test "returns identical results to Metastatic.Analysis.Purity" do
      ast = {:function_call, [name: "print"], [{:literal, [subtype: :string], "hello"}]}
      doc = Document.new(ast, :python)

      {:ok, meta_result} = Metastatic.Analysis.Purity.analyze(doc)
      {:ok, mc_result} = Purity.analyze(doc)

      assert meta_result.pure? == mc_result.pure?
      assert meta_result.effects == mc_result.effects
      assert meta_result.confidence == mc_result.confidence
    end
  end
end
