defmodule MetaCredo.Check.Design.TagScan do
  @moduledoc """
  Shared comment-scanning helpers for the `TagTodo` / `TagFixme` checks.

  These helpers exist to satisfy two requirements:

    1. **Configurable patterns** -- the tag to look for is supplied as a
       list of strings or regexes (via the `:tags` param in
       `.metacredo.exs`), not hardcoded.

    2. **Comment-only matches** -- a match is only reported when it is
       genuinely *inside a comment*. Naively scanning raw source lines
       (as the original implementation did) flags the tag wherever it
       appears -- inside string literals, variable names, function names,
       `@moduledoc` prose, etc. -- which is almost always a false
       positive. This module extracts the comment portion of a line and
       only searches *that*.

  ## Why source-line scanning is needed at all

  Some language adapters (notably Elixir) strip comments from the AST --
  Elixir's tokenizer discards them, so no `{:comment, _, _}` node ever
  reaches the MetaAST. For those languages the only way to see a comment
  is to re-read the raw source. The AST path is still used for languages
  whose adapters *do* surface `:comment` nodes (e.g. Cure); the source
  scan is the fallback for everything else.
  """

  @doc """
  Compiles a list of tag patterns (strings or regexes) into a single
  case-insensitive regex.

  String patterns are escaped and matched literally (so `"TODO"` does not
  accidentally behave as a regex), while `Regex` patterns are used as-is.
  Returns `nil` when the list is empty or contains no usable patterns.

  ## Examples

      iex> TagScan.compile_tags(["TODO"])
      ~r/(?:TODO)/i

      iex> TagScan.compile_tags([~r/TODO|FIXME/])
      ~r/TODO|FIXME/i

      iex> TagScan.compile_tags([])
      nil
  """
  @spec compile_tags([String.t() | Regex.t()]) :: Regex.t() | nil
  def compile_tags(tags) when is_list(tags) do
    sources =
      tags
      |> Enum.map(&pattern_source/1)
      |> Enum.reject(&is_nil/1)

    case sources do
      [] -> nil
      _ -> Regex.compile!("(?:#{Enum.join(sources, "|")})", "i")
    end
  end

  def compile_tags(_), do: nil

  @doc """
  Returns `true` when `text` contains a match for the compiled tag regex.

  A `nil` regex (i.e. no configured tags) never matches.
  """
  @spec matches?(Regex.t() | nil, String.t()) :: boolean()
  def matches?(nil, _text), do: false
  def matches?(%Regex{} = regex, text) when is_binary(text), do: Regex.match?(regex, text)
  def matches?(_, _), do: false

  @doc """
  Extracts the comment portion of a single source line for the given
  language, or `nil` when the line contains no comment.

  The extraction is string-aware: a comment marker that appears inside a
  string literal (e.g. `"http://example.com"` or `"a # b"`) is *not*
  treated as the start of a comment. Only the returned comment text
  should be searched for tags.

  ## Examples

      iex> TagScan.comment_text("x = 1  # TODO: fix", :elixir)
      "TODO: fix"

      iex> TagScan.comment_text("url = \\"http://x\\"", :elixir)
      nil

      iex> TagScan.comment_text("const x = 1; // FIXME", :javascript)
      "FIXME"
  """
  @spec comment_text(String.t(), atom()) :: String.t() | nil
  def comment_text(line, language) when is_binary(line) do
    case comment_marker(language) do
      {:line, markers} -> line_comment_text(line, markers)
      :none -> nil
    end
  end

  def comment_text(_line, _language), do: nil

  # -- Private --

  defp pattern_source(%Regex{} = regex), do: Regex.source(regex)
  defp pattern_source(pattern) when is_binary(pattern), do: Regex.escape(pattern)
  defp pattern_source(_), do: nil

  # Comment syntax by language. Languages not listed fall back to `:none`
  # (no source-line scanning) rather than guessing and risking false
  # positives.
  #
  # Rust was previously missing from this table, so `// TODO:` in a `.rs`
  # file never matched and `TagTodo`/`TagFixme` were silently dead on Rust
  # source -- the check reported nothing while the same comment in an Elixir
  # file was flagged. Rust uses `//` for line comments, exactly as
  # JavaScript and TypeScript do.
  defp comment_marker(:elixir), do: {:line, ["#"]}
  defp comment_marker(:ruby), do: {:line, ["#"]}
  defp comment_marker(:python), do: {:line, ["#"]}
  defp comment_marker(:cure), do: {:line, ["#"]}
  defp comment_marker(:haskell), do: {:line, ["--"]}
  defp comment_marker(:javascript), do: {:line, ["//"]}
  defp comment_marker(:typescript), do: {:line, ["//"]}
  defp comment_marker(:rust), do: {:line, ["//"]}
  defp comment_marker(:erlang), do: {:line, ["%"]}
  defp comment_marker(_), do: :none

  # Finds the first comment marker that is *outside* any string literal
  # and returns the text following it.
  defp line_comment_text(line, markers) do
    case find_marker(line, markers) do
      nil ->
        nil

      index ->
        line
        |> binary_part(index, byte_size(line) - index)
        |> trim_marker(markers)
    end
  end

  defp trim_marker(text, markers) do
    Enum.find_value(markers, text, fn marker ->
      if String.starts_with?(text, marker) do
        text
        |> binary_part(byte_size(marker), byte_size(text) - byte_size(marker))
        |> String.trim_leading()
      end
    end)
  end

  defp find_marker(line, markers) do
    do_find_marker(line, markers, 0, nil)
  end

  # Walk the line character by character, tracking whether we are inside a
  # string literal, and return the byte offset of the first marker found
  # outside a string.
  defp do_find_marker(<<>>, _markers, _offset, _quote), do: nil

  defp do_find_marker(rest, markers, offset, nil) do
    case String.next_grapheme(rest) do
      {grapheme, tail} ->
        cond do
          # An Elixir sigil (`~r/.../`, `~s(...)`) is a string literal: a `#`
          # inside its body is not a comment marker. Detect `~` + letter +
          # delimiter and skip the whole sigil.
          grapheme == "~" ->
            case skip_sigil(rest) do
              {:ok, skipped_bytes} ->
                do_find_marker(
                  binary_part(rest, skipped_bytes, byte_size(rest) - skipped_bytes),
                  markers,
                  offset + skipped_bytes,
                  nil
                )

              :error ->
                do_find_marker(tail, markers, offset + byte_size(grapheme), nil)
            end

          grapheme in ["\"", "'"] ->
            do_find_marker(tail, markers, offset + byte_size(grapheme), grapheme)

          marker_at?(rest, markers) ->
            offset

          true ->
            do_find_marker(tail, markers, offset + byte_size(grapheme), nil)
        end

      nil ->
        nil
    end
  end

  defp do_find_marker(rest, markers, offset, quote) do
    case String.next_grapheme(rest) do
      {grapheme, tail} ->
        cond do
          grapheme == quote ->
            do_find_marker(tail, markers, offset + byte_size(grapheme), nil)

          grapheme == "\\" ->
            # Skip the escaped character.
            case String.next_grapheme(tail) do
              {escaped, tail2} ->
                do_find_marker(
                  tail2,
                  markers,
                  offset + byte_size(grapheme) + byte_size(escaped),
                  quote
                )

              nil ->
                nil
            end

          true ->
            do_find_marker(tail, markers, offset + byte_size(grapheme), quote)
        end

      nil ->
        nil
    end
  end

  defp marker_at?(rest, markers) do
    Enum.any?(markers, &String.starts_with?(rest, &1))
  end

  # Elixir sigil delimiters. Paired delimiters nest; single ones do not.
  @sigil_pairs %{"(" => ")", "[" => "]", "{" => "}", "<" => ">"}
  @sigil_singles ~W(/ | " ')

  # `rest` starts at the `~`. Returns `{:ok, byte_size}` covering the whole
  # sigil when it is well formed on this line, or `:error` when it is not a
  # sigil (or the sigil is unterminated, e.g. a multi-line heredoc).
  defp skip_sigil("~" <> after_tilde = rest) do
    with {letter, after_letter} <- String.next_grapheme(after_tilde),
         true <- letter?(letter),
         {delimiter, body} <- String.next_grapheme(after_letter),
         true <- delimiter in Map.keys(@sigil_pairs) or delimiter in @sigil_singles do
      closing = Map.get(@sigil_pairs, delimiter, delimiter)
      # Everything up to and including the opening delimiter.
      prefix_bytes = byte_size(rest) - byte_size(body)

      case find_closing(body, closing, 0) do
        {:ok, relative} -> {:ok, prefix_bytes + relative}
        :error -> :error
      end
    else
      _ -> :error
    end
  end

  defp skip_sigil(_), do: :error

  # Sigils are `~` + one or more letters + a delimiter. Only the first letter
  # is inspected; multi-letter sigils (`~S`, `~r`) and custom ones (`~x`) all
  # share the shape.
  defp letter?(grapheme) when is_binary(grapheme) do
    grapheme in Enum.map(?a..?z, &<<&1>>) or grapheme in Enum.map(?A..?Z, &<<&1>>)
  end

  # Walks from just after the opening delimiter to the matching closing one,
  # honouring backslash escapes. Returns the byte offset *past* the closing
  # delimiter, relative to `rest`.
  defp find_closing(rest, closing, consumed) do
    case String.next_grapheme(rest) do
      nil ->
        :error

      {grapheme, tail} ->
        cond do
          grapheme == closing ->
            {:ok, consumed + byte_size(grapheme)}

          grapheme == "\\" ->
            case String.next_grapheme(tail) do
              {escaped, tail2} ->
                find_closing(tail2, closing, consumed + byte_size(grapheme) + byte_size(escaped))

              nil ->
                :error
            end

          true ->
            find_closing(tail, closing, consumed + byte_size(grapheme))
        end
    end
  end
end
