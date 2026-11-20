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

  describe "effect classification (regression: bare local calls)" do
    # A bare local call like `timeout(5000)` or `update_counters/2` is an
    # ordinary project function. Prefix-matching its *name* used to classify it
    # as a `:time` / `:database` effect, reporting pure code as impure.
    test "bare local calls are not given a spurious effect" do
      for name <- ~w(timeout read_config update_counters random_bytes fetch_data) do
        ast = {:function_call, [name: name], []}

        assert {:ok, result} = Purity.analyze(Document.new(ast, :elixir))
        assert result.effects == [], "#{name}/0 was given effects #{inspect(result.effects)}"
      end
    end

    test "qualified calls are still classified" do
      for {name, effect} <- [
            {"File.read!", :io},
            {"IO.puts", :io},
            {":rand.uniform", :random},
            {"Repo.insert", :database},
            {"HTTPoison.get", :network}
          ] do
        ast = {:function_call, [name: name], []}

        assert {:ok, result} = Purity.analyze(Document.new(ast, :elixir))
        assert effect in result.effects, "#{name} was not classified as #{effect}"
      end
    end

    test "known-pure stdlib calls do not downgrade a function to unknown" do
      for name <- ~w(Map.get String.trim Enum.map) do
        ast = {:function_call, [name: name], []}

        assert {:ok, result} = Purity.analyze(Document.new(ast, :elixir))
        assert result.pure?, "#{name} should not make the function impure"
        assert result.effects == []
      end
    end
  end
end
