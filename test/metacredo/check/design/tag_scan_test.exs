defmodule MetaCredo.Check.Design.TagScanTest do
  use ExUnit.Case, async: true

  alias MetaCredo.Check.Design.TagScan

  describe "compile_tags/1" do
    test "compiles a list of string tags into a case-insensitive regex" do
      regex = TagScan.compile_tags(["TODO"])
      assert Regex.match?(regex, "TODO")
      assert Regex.match?(regex, "todo")
      assert Regex.match?(regex, "a Todo b")
      refute Regex.match?(regex, "FIXME")
    end

    test "escapes string tags so they match literally" do
      regex = TagScan.compile_tags(["T.DO"])
      refute Regex.match?(regex, "TODO")
      assert Regex.match?(regex, "T.DO")
    end

    test "accepts regex tags as-is" do
      regex = TagScan.compile_tags([~r/XXX|YYY/])
      assert Regex.match?(regex, "XXX")
      assert Regex.match?(regex, "yyy")
      refute Regex.match?(regex, "TODO")
    end

    test "combines string and regex tags" do
      regex = TagScan.compile_tags(["TODO", ~r/XXX/])
      assert Regex.match?(regex, "TODO")
      assert Regex.match?(regex, "xxx")
      refute Regex.match?(regex, "HACK")
    end

    test "returns nil for an empty list" do
      assert TagScan.compile_tags([]) == nil
    end

    test "returns nil for non-list input" do
      assert TagScan.compile_tags(:nope) == nil
    end
  end

  describe "matches?/2" do
    test "matches against the compiled regex" do
      regex = TagScan.compile_tags(["TODO"])
      assert TagScan.matches?(regex, "TODO: fix")
      refute TagScan.matches?(regex, "no tag here")
    end

    test "never matches when the regex is nil" do
      refute TagScan.matches?(nil, "TODO: fix")
    end
  end

  describe "comment_text/2" do
    test "extracts an inline Elixir comment" do
      assert TagScan.comment_text("x = 1  # TODO: fix", :elixir) == "TODO: fix"
    end

    test "extracts a whole-line Elixir comment" do
      assert TagScan.comment_text("# TODO: fix", :elixir) == "TODO: fix"
    end

    test "returns nil when there is no comment" do
      assert TagScan.comment_text("x = 1", :elixir) == nil
    end

    test "ignores a # inside a double-quoted string" do
      assert TagScan.comment_text(~S(msg = "a # b"), :elixir) == nil
    end

    test "ignores a # inside a single-quoted string" do
      assert TagScan.comment_text(~S(msg = 'a # b'), :elixir) == nil
    end

    test "ignores a # inside a string that looks like a URL fragment" do
      assert TagScan.comment_text(~S(label = "issue #42 not a comment"), :elixir) == nil
    end

    test "handles an escaped quote inside a string" do
      assert TagScan.comment_text(~S(msg = "a \" # b"), :elixir) == nil
    end

    test "finds the comment after a closed string" do
      assert TagScan.comment_text(~S(msg = "text" # TODO), :elixir) == "TODO"
    end

    test "extracts a JavaScript line comment" do
      assert TagScan.comment_text("const x = 1; // FIXME", :javascript) == "FIXME"
    end

    test "extracts a Haskell line comment" do
      assert TagScan.comment_text("x = 1 -- TODO", :haskell) == "TODO"
    end

    test "extracts an Erlang line comment" do
      assert TagScan.comment_text("X = 1. % TODO", :erlang) == "TODO"
    end

    test "returns nil for languages without a configured marker" do
      assert TagScan.comment_text("# TODO", :unknown_language) == nil
    end

    test "returns nil for non-binary input" do
      assert TagScan.comment_text(nil, :elixir) == nil
    end

    # A sigil (`~r/.../`, `~s(...)`) is a string literal in Elixir: a `#`
    # inside its body is not a comment marker. The scanner previously treated
    # it as one, truncating the line at the wrong offset.
    test "ignores a # inside a regex sigil" do
      assert TagScan.comment_text("  @pattern ~r/FIXME#anchor/ ", :elixir) == nil
    end

    test "ignores a # inside a paren-delimited sigil" do
      assert TagScan.comment_text("  @re ~s(a#b)", :elixir) == nil
    end

    test "ignores a # inside a brace-delimited sigil" do
      assert TagScan.comment_text("  @re ~r{a#b}", :elixir) == nil
    end

    test "still finds a real comment after a sigil" do
      assert TagScan.comment_text("  @re ~s(a#b) # FIXME real", :elixir) == "FIXME real"
    end

    test "still finds a real comment after a regex sigil" do
      assert TagScan.comment_text("  @re ~r/x#y/ # TODO here", :elixir) == "TODO here"
    end

    test "falls back safely when the sigil is unterminated on the line" do
      # A multi-line heredoc sigil cannot be resolved from one line; the
      # scanner must not crash and must not invent a comment.
      assert TagScan.comment_text("  @re ~r/abc", :elixir) == nil
    end
  end
end
