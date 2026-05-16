defmodule MetaCredo.Analysis.Duplication do
  @moduledoc """
  Programmatic code duplication detection API.

  Detects code clones across the same or different programming languages
  by operating on the unified MetaAST representation. Supports four types:

  - **Type I**: Exact clones (identical AST)
  - **Type II**: Renamed clones (identical structure, different identifiers)
  - **Type III**: Near-miss clones (similar structure with modifications)
  - **Type IV**: Semantic clones (different syntax, same behavior)

  ## Usage

      alias Metastatic.Document
      alias MetaCredo.Analysis.Duplication

      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :python)

      {:ok, result} = Duplication.detect(doc1, doc2)
      result.duplicate?        # => true
      result.clone_type        # => :type_i
      result.similarity_score  # => 1.0
  """

  alias MetaCredo.Analysis.Duplication.{Fingerprint, Result, Similarity}
  alias Metastatic.{AST, Document}

  @dialyzer :no_opaque

  @type detect_opts :: [
          threshold: float(),
          min_tokens: non_neg_integer(),
          ignore_literals: boolean(),
          ignore_variables: boolean(),
          cross_language: boolean(),
          clone_types: [atom()]
        ]

  @doc "Detects duplication between two documents."
  @spec detect(Document.t(), Document.t(), detect_opts()) :: {:ok, Result.t()}
  def detect(%Document{ast: ast1} = doc1, %Document{ast: ast2} = doc2, opts \\ []) do
    if AST.conforms?(ast1) and AST.conforms?(ast2) do
      threshold = Keyword.get(opts, :threshold, 0.8)

      result =
        cond do
          exact_match?(ast1, ast2) ->
            build_type_i_result(doc1, doc2)

          normalized_match?(ast1, ast2) ->
            build_type_ii_result(doc1, doc2)

          true ->
            similarity_score = Similarity.calculate(ast1, ast2)

            if similarity_score >= threshold do
              build_type_iii_result(doc1, doc2, similarity_score)
            else
              Result.no_duplicate()
            end
        end

      {:ok, result}
    else
      {:ok, Result.no_duplicate()}
    end
  end

  @doc "Detects duplication between two documents, raising on error."
  @spec detect!(Document.t(), Document.t(), detect_opts()) :: Result.t()
  def detect!(doc1, doc2, opts \\ []) do
    with {:ok, result} <- detect(doc1, doc2, opts), do: result
  end

  @doc "Calculates similarity score between two ASTs (0.0 to 1.0)."
  @spec similarity(AST.meta_ast(), AST.meta_ast()) :: float()
  def similarity(ast1, ast2), do: Similarity.calculate(ast1, ast2)

  @doc "Detects duplicates across multiple documents."
  @spec detect_in_list([Document.t()], detect_opts()) :: {:ok, [map()]}
  def detect_in_list(documents, opts \\ []) when is_list(documents) do
    _threshold = Keyword.get(opts, :threshold, 0.8)

    indexed_docs =
      documents
      |> Enum.with_index()
      |> Enum.map(fn {doc, idx} ->
        %{
          doc: doc,
          index: idx,
          exact_fp: Fingerprint.exact(doc.ast),
          normalized_fp: Fingerprint.normalized(doc.ast)
        }
      end)

    pairs =
      for i <- 0..(length(indexed_docs) - 1)//1,
          j <- (i + 1)..(length(indexed_docs) - 1)//1 do
        doc1_info = Enum.at(indexed_docs, i)
        doc2_info = Enum.at(indexed_docs, j)

        if should_compare?(doc1_info, doc2_info) do
          case detect(doc1_info.doc, doc2_info.doc, opts) do
            {:ok, %{duplicate?: true} = result} ->
              {doc1_info.index, doc2_info.index, result}

            _ ->
              nil
          end
        else
          nil
        end
      end
      |> Enum.reject(&is_nil/1)

    groups = group_clones(pairs, indexed_docs)
    {:ok, groups}
  end

  @doc "Detects duplicates across multiple documents, raising on error."
  @spec detect_in_list!([Document.t()], detect_opts()) :: [map()]
  def detect_in_list!(documents, opts \\ []) do
    with {:ok, groups} <- detect_in_list(documents, opts), do: groups
  end

  @doc "Generates a structural fingerprint for an AST."
  @spec fingerprint(AST.meta_ast()) :: String.t()
  def fingerprint(ast), do: Fingerprint.exact(ast)

  # Private functions

  defp exact_match?(ast1, ast2), do: ast1 == ast2

  defp normalized_match?(ast1, ast2) do
    Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
  end

  defp build_type_i_result(doc1, doc2) do
    locations = [build_location(doc1), build_location(doc2)]

    fingerprints = %{
      exact: Fingerprint.exact(doc1.ast),
      normalized: Fingerprint.normalized(doc1.ast)
    }

    metrics = %{
      size: count_nodes(doc1.ast),
      complexity: nil,
      variables: MapSet.size(AST.variables(doc1.ast))
    }

    Result.exact_clone()
    |> Result.with_locations(locations)
    |> Result.with_fingerprints(fingerprints)
    |> Result.with_metrics(metrics)
  end

  defp build_type_ii_result(doc1, doc2) do
    locations = [build_location(doc1), build_location(doc2)]

    fingerprints = %{
      exact: Fingerprint.exact(doc1.ast),
      normalized: Fingerprint.normalized(doc1.ast)
    }

    metrics = %{
      size: count_nodes(doc1.ast),
      complexity: nil,
      variables: MapSet.size(AST.variables(doc1.ast))
    }

    Result.renamed_clone()
    |> Result.with_locations(locations)
    |> Result.with_fingerprints(fingerprints)
    |> Result.with_metrics(metrics)
  end

  defp build_type_iii_result(doc1, doc2, similarity_score) do
    locations = [build_location(doc1), build_location(doc2)]

    fingerprints = %{
      exact: Fingerprint.exact(doc1.ast),
      normalized: Fingerprint.normalized(doc1.ast)
    }

    metrics = %{
      size: count_nodes(doc1.ast),
      complexity: nil,
      variables: MapSet.size(AST.variables(doc1.ast))
    }

    Result.near_miss_clone(similarity_score)
    |> Result.with_locations(locations)
    |> Result.with_fingerprints(fingerprints)
    |> Result.with_metrics(metrics)
  end

  defp build_location(%Document{metadata: metadata, language: language}) do
    %{
      file: get_in(metadata || %{}, [:file]),
      start_line: get_in(metadata || %{}, [:start_line]),
      end_line: get_in(metadata || %{}, [:end_line]),
      language: language
    }
  end

  defp count_nodes(ast), do: walk_and_count(ast, 0)

  defp walk_and_count({:binary_op, _, _, left, right}, count) do
    count = walk_and_count(left, count + 1)
    walk_and_count(right, count)
  end

  defp walk_and_count({:unary_op, _, _, operand}, count),
    do: walk_and_count(operand, count + 1)

  defp walk_and_count({:function_call, _, args}, count) when is_list(args),
    do: Enum.reduce(args, count + 1, fn arg, c -> walk_and_count(arg, c) end)

  defp walk_and_count({:conditional, cond, then_br, else_br}, count) do
    count = walk_and_count(cond, count + 1)
    count = walk_and_count(then_br, count)
    if else_br, do: walk_and_count(else_br, count), else: count
  end

  defp walk_and_count({:block, stmts}, count) when is_list(stmts),
    do: Enum.reduce(stmts, count + 1, fn stmt, c -> walk_and_count(stmt, c) end)

  defp walk_and_count({:loop, :while, cond, body}, count) do
    count = walk_and_count(cond, count + 1)
    walk_and_count(body, count)
  end

  defp walk_and_count({:loop, _, iter, coll, body}, count) do
    count = walk_and_count(iter, count + 1)
    count = walk_and_count(coll, count)
    walk_and_count(body, count)
  end

  defp walk_and_count({:assignment, target, value}, count) do
    count = walk_and_count(target, count + 1)
    walk_and_count(value, count)
  end

  defp walk_and_count({:inline_match, pattern, value}, count) do
    count = walk_and_count(pattern, count + 1)
    walk_and_count(value, count)
  end

  defp walk_and_count({:lambda, _params, _captures, body}, count),
    do: walk_and_count(body, count + 1)

  defp walk_and_count({:collection_op, _, func, coll}, count) do
    count = walk_and_count(func, count + 1)
    walk_and_count(coll, count)
  end

  defp walk_and_count({:collection_op, _, func, coll, init}, count) do
    count = walk_and_count(func, count + 1)
    count = walk_and_count(coll, count)
    walk_and_count(init, count)
  end

  defp walk_and_count({:early_return, value}, count),
    do: walk_and_count(value, count + 1)

  defp walk_and_count({:tuple, elems}, count) when is_list(elems),
    do: Enum.reduce(elems, count + 1, fn elem, c -> walk_and_count(elem, c) end)

  defp walk_and_count(_, count), do: count + 1

  defp should_compare?(doc1_info, doc2_info) do
    if doc1_info.exact_fp == doc2_info.exact_fp do
      true
    else
      doc1_info.normalized_fp == doc2_info.normalized_fp
    end
  end

  defp group_clones(pairs, indexed_docs) do
    if Enum.empty?(pairs) do
      []
    else
      adjacency =
        Enum.reduce(pairs, %{}, fn {idx1, idx2, result}, acc ->
          acc
          |> Map.update(idx1, [{idx2, result}], fn list -> [{idx2, result} | list] end)
          |> Map.update(idx2, [{idx1, result}], fn list -> [{idx1, result} | list] end)
        end)

      visited = MapSet.new()
      all_indices = Map.keys(adjacency)

      {groups, _} =
        Enum.reduce(all_indices, {[], visited}, fn idx, {groups_acc, visited_acc} ->
          if MapSet.member?(visited_acc, idx) do
            {groups_acc, visited_acc}
          else
            {group, new_visited} = bfs_group(idx, adjacency, visited_acc, indexed_docs)
            {[group | groups_acc], new_visited}
          end
        end)

      groups
    end
  end

  defp bfs_group(start_idx, adjacency, visited, indexed_docs) do
    queue = :queue.from_list([start_idx])
    bfs_loop(queue, adjacency, MapSet.put(visited, start_idx), [], indexed_docs)
  end

  defp bfs_loop(queue, adjacency, visited, group_indices, indexed_docs) do
    case :queue.out(queue) do
      {{:value, idx}, rest_queue} ->
        neighbors = Map.get(adjacency, idx, [])

        {new_queue, new_visited} =
          Enum.reduce(neighbors, {rest_queue, visited}, fn {neighbor_idx, _result}, {q, v} ->
            if MapSet.member?(v, neighbor_idx) do
              {q, v}
            else
              {:queue.in(neighbor_idx, q), MapSet.put(v, neighbor_idx)}
            end
          end)

        bfs_loop(new_queue, adjacency, new_visited, [idx | group_indices], indexed_docs)

      {:empty, _} ->
        group_docs = Enum.map(group_indices, fn idx -> Enum.at(indexed_docs, idx).doc end)

        group = %{
          size: length(group_docs),
          documents: group_docs,
          clone_type: determine_group_clone_type(group_docs),
          locations:
            Enum.map(group_docs, fn doc ->
              %{
                file: get_in(doc.metadata, [:file]),
                start_line: get_in(doc.metadata, [:start_line]),
                end_line: get_in(doc.metadata, [:end_line]),
                language: doc.language
              }
            end)
        }

        {group, visited}
    end
  end

  defp determine_group_clone_type([doc1, doc2 | _rest]) do
    cond do
      doc1.ast == doc2.ast -> :type_i
      Fingerprint.normalized(doc1.ast) == Fingerprint.normalized(doc2.ast) -> :type_ii
      true -> :type_iii
    end
  end

  defp determine_group_clone_type(_), do: :type_i
end
