defmodule MetaCredo.Analysis.Duplication.FingerprintTest do
  use ExUnit.Case, async: true

  alias MetaCredo.Analysis.Duplication.Fingerprint

  @map_ast_pairs {:map, [line: 1],
                  [
                    {:pair, [line: 1],
                     [{:literal, [subtype: :symbol], :a}, {:literal, [subtype: :integer], 1}]},
                    {:pair, [line: 1],
                     [{:literal, [subtype: :symbol], :b}, {:literal, [subtype: :integer], 2}]}
                  ]}

  @map_ast_pairs_renamed {:map, [line: 2],
                          [
                            {:pair, [line: 2],
                             [
                               {:literal, [subtype: :symbol], :x},
                               {:literal, [subtype: :integer], 10}
                             ]},
                            {:pair, [line: 2],
                             [
                               {:literal, [subtype: :symbol], :y},
                               {:literal, [subtype: :integer], 20}
                             ]}
                          ]}

  @map_ast_2tuples {:map, [],
                    [
                      {{:literal, [subtype: :symbol], :a}, {:literal, [subtype: :integer], 1}},
                      {{:literal, [subtype: :symbol], :b}, {:literal, [subtype: :integer], 2}}
                    ]}

  describe "normalized/1" do
    test "normalizes variables and literals in binary expressions" do
      ast1 =
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:variable, [], "a"}, {:literal, [subtype: :integer], 1}]}

      ast2 =
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:variable, [], "b"}, {:literal, [subtype: :integer], 2}]}

      assert Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
    end

    test "normalizes maps containing 3-tuple :pair entries" do
      assert is_binary(Fingerprint.normalized(@map_ast_pairs))

      assert Fingerprint.normalized(@map_ast_pairs) ==
               Fingerprint.normalized(@map_ast_pairs_renamed)
    end

    test "normalizes maps containing 2-tuple entries" do
      assert is_binary(Fingerprint.normalized(@map_ast_2tuples))
    end

    test "handles standalone :pair nodes" do
      pair = {:pair, [], [{:variable, [], "x"}, {:literal, [subtype: :integer], 42}]}
      assert is_binary(Fingerprint.normalized(pair))
    end

    test "handles 2-element conditionals" do
      cond_ast = {:conditional, [], [{:variable, [], "flag"}, {:literal, [subtype: :integer], 1}]}
      assert is_binary(Fingerprint.normalized(cond_ast))
    end

    test "does not crash on unknown or malformed AST nodes" do
      malformed_ast = {:unknown_node, [foo: :bar], :not_a_list_either}
      assert is_binary(Fingerprint.normalized(malformed_ast))
    end
  end

  describe "tokens/1" do
    test "extracts tokens from maps with 3-tuple :pair entries" do
      tokens = Fingerprint.tokens(@map_ast_pairs)
      assert :map in tokens
      assert :literal in tokens
      assert :integer in tokens
      assert :symbol in tokens
    end

    test "extracts tokens from maps with 2-tuple entries" do
      tokens = Fingerprint.tokens(@map_ast_2tuples)
      assert :map in tokens
      assert :literal in tokens
    end

    test "extracts tokens from 2-element conditional" do
      cond_ast = {:conditional, [], [{:variable, [], "flag"}, {:literal, [subtype: :integer], 1}]}
      tokens = Fingerprint.tokens(cond_ast)
      assert :conditional in tokens
      assert :variable in tokens
    end

    test "does not crash on malformed AST in tokens/1" do
      malformed = {:unexpected_construct}
      assert is_list(Fingerprint.tokens(malformed))
    end
  end

  describe "match?/2" do
    test "matches identical fingerprints" do
      fp1 = Fingerprint.exact(@map_ast_pairs)
      fp2 = Fingerprint.exact(@map_ast_pairs)
      assert Fingerprint.match?(fp1, fp2)
    end

    test "does not match different fingerprints" do
      fp1 = Fingerprint.exact(@map_ast_pairs)
      fp2 = Fingerprint.exact(@map_ast_pairs_renamed)
      refute Fingerprint.match?(fp1, fp2)
    end
  end
end
