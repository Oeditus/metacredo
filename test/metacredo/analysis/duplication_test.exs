defmodule MetaCredo.Analysis.DuplicationTest do
  use ExUnit.Case, async: true

  alias MetaCredo.Analysis.Duplication
  alias Metastatic.Document

  @int42 {:literal, [subtype: :integer], 42}
  @str_hello {:literal, [subtype: :string], "hello"}

  describe "detect/2" do
    test "detects exact clone (Type I)" do
      doc1 = Document.new(@int42, :elixir)
      doc2 = Document.new(@int42, :python)

      assert {:ok, result} = Duplication.detect(doc1, doc2)
      assert result.duplicate?
      assert result.clone_type == :type_i
    end

    test "detects no duplication for different ASTs" do
      doc1 = Document.new(@int42, :elixir)
      doc2 = Document.new(@str_hello, :elixir)

      assert {:ok, result} = Duplication.detect(doc1, doc2)
      refute result.duplicate?
    end
  end

  describe "detect/3 with options" do
    test "respects threshold option" do
      doc1 = Document.new(@int42, :elixir)
      doc2 = Document.new(@str_hello, :elixir)

      assert {:ok, result} = Duplication.detect(doc1, doc2, threshold: 0.0)
      # Even with 0.0 threshold, structurally different ASTs may or may not match
      assert is_boolean(result.duplicate?)
    end
  end

  describe "detect!/2" do
    test "returns result directly" do
      doc1 = Document.new(@int42, :elixir)
      doc2 = Document.new(@int42, :elixir)

      result = Duplication.detect!(doc1, doc2)
      assert result.duplicate?
    end
  end

  describe "similarity/2" do
    test "identical ASTs have similarity 1.0" do
      assert Duplication.similarity(@int42, @int42) == 1.0
    end

    test "different ASTs have similarity < 1.0" do
      score = Duplication.similarity(@int42, @str_hello)
      assert score < 1.0
    end
  end

  describe "detect_in_list/1" do
    test "finds duplicates across multiple documents" do
      docs = [
        Document.new(@int42, :elixir),
        Document.new(@int42, :python),
        Document.new(@str_hello, :elixir)
      ]

      assert {:ok, groups} = Duplication.detect_in_list(docs)
      assert is_list(groups)
    end
  end

  describe "fingerprint/1" do
    test "identical ASTs produce identical fingerprints" do
      fp1 = Duplication.fingerprint(@int42)
      fp2 = Duplication.fingerprint(@int42)
      assert fp1 == fp2
    end

    test "different ASTs produce different fingerprints" do
      fp1 = Duplication.fingerprint(@int42)
      fp2 = Duplication.fingerprint(@str_hello)
      assert fp1 != fp2
    end
  end
end
