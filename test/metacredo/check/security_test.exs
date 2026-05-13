defmodule MetaCredo.Check.SecurityTest do
  use MetaCredo.CheckCase

  alias MetaCredo.Check.Security

  # ── HardcodedValue ─────────────────────────────────────────────────

  describe "HardcodedValue" do
    test "detects hardcoded HTTPS URL" do
      issues =
        run_check(Security.HardcodedValue,
          ast: literal_string("https://api.example.com/v1", line: 5)
        )

      assert_issue(issues, category: :security, line_no: 5)
      assert_issue(issues, message: ~r/Hardcoded URL/)
    end

    test "detects hardcoded HTTP URL" do
      issues =
        run_check(Security.HardcodedValue,
          ast: literal_string("http://prod.myapp.io/api", line: 3)
        )

      assert_issue_count(issues, 1)
    end

    test "skips localhost URLs by default" do
      for url <- ["http://localhost:4000", "http://127.0.0.1:3000", "http://0.0.0.0:8080"] do
        issues = run_check(Security.HardcodedValue, ast: literal_string(url))
        assert_no_issues(issues)
      end
    end

    test "flags localhost URLs when exclude_localhost: false" do
      issues =
        run_check(Security.HardcodedValue,
          ast: literal_string("http://localhost:4000", line: 1),
          params: [exclude_localhost: false]
        )

      assert_issue_count(issues, 1)
    end

    test "detects public IP addresses" do
      for ip <- ["8.8.8.8", "1.1.1.1", "203.0.113.50"] do
        issues = run_check(Security.HardcodedValue, ast: literal_string(ip, line: 1))
        assert_issue(issues, message: ~r/IP address/)
      end
    end

    test "skips private IP ranges by default" do
      for ip <- ["192.168.1.1", "10.0.0.1", "127.0.0.1", "0.0.0.0"] do
        issues = run_check(Security.HardcodedValue, ast: literal_string(ip))
        assert_no_issues(issues)
      end
    end

    test "flags private IPs when exclude_local_ips: false" do
      issues =
        run_check(Security.HardcodedValue,
          ast: literal_string("192.168.1.1", line: 1),
          params: [exclude_local_ips: false]
        )

      assert_issue_count(issues, 1)
    end

    test "ignores non-string literals" do
      issues =
        run_check(Security.HardcodedValue,
          ast: literal_int(42, line: 1)
        )

      assert_no_issues(issues)
    end

    test "ignores regular strings" do
      issues =
        run_check(Security.HardcodedValue,
          ast: literal_string("hello world", line: 1)
        )

      assert_no_issues(issues)
    end

    test "ignores invalid IP-like strings" do
      issues =
        run_check(Security.HardcodedValue,
          ast: literal_string("999.999.999.999", line: 1)
        )

      assert_no_issues(issues)
    end

    test "properly categorizes all issues as :security" do
      ast =
        block([
          literal_string("https://api.example.com", line: 1),
          literal_string("8.8.8.8", line: 2)
        ])

      issues = run_check(Security.HardcodedValue, ast: ast)
      assert_all_category(issues, :security)
    end
  end

  # ── SQLInjection ───────────────────────────────────────────────────

  describe "SQLInjection" do
    @tag :sql_injection
    test "detects SQL string concatenation with variable" do
      ast =
        binop(
          :string,
          :<>,
          literal_string("SELECT * FROM users WHERE id = ", line: 10),
          var("user_id"),
          line: 10
        )

      issues = run_check(Security.SQLInjection, ast: ast)
      assert_issue(issues, message: ~r/SQL injection/)
    end

    test "detects query function with concatenated arg" do
      concat = binop(:string, :<>, literal_string("SELECT * FROM users WHERE id = "), var("id"))

      ast = call("Repo.query", [concat], line: 5)
      issues = run_check(Security.SQLInjection, ast: ast)
      assert_issue(issues, category: :security)
    end

    test "ignores plain string literals" do
      ast = literal_string("SELECT * FROM users", line: 1)
      issues = run_check(Security.SQLInjection, ast: ast)
      assert_no_issues(issues)
    end

    test "ignores non-SQL concatenation" do
      ast = binop(:string, :<>, literal_string("hello "), var("name"), line: 1)

      issues = run_check(Security.SQLInjection, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── XSSVulnerability ───────────────────────────────────────────────

  describe "XSSVulnerability" do
    test "detects raw() call" do
      ast = call("raw", [var("user_input")], line: 15)
      issues = run_check(Security.XSSVulnerability, ast: ast)
      assert_issue(issues, message: ~r/XSS/)
    end

    test "detects html_safe call" do
      ast = call("html_safe", [var("content")], line: 8)
      issues = run_check(Security.XSSVulnerability, ast: ast)
      assert_issue(issues, category: :security)
    end

    test "detects dangerouslySetInnerHTML" do
      ast = call("dangerouslySetInnerHTML", [var("data")], line: 3)
      issues = run_check(Security.XSSVulnerability, ast: ast)
      assert_issue(issues, message: ~r/XSS/)
    end

    test "ignores safe function calls" do
      ast = call("render", [literal_string("template.html")], line: 1)
      issues = run_check(Security.XSSVulnerability, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── PathTraversal ──────────────────────────────────────────────────

  describe "PathTraversal" do
    test "detects file read with user input variable" do
      ast = call("send_file", [var("filename")], line: 12)
      issues = run_check(Security.PathTraversal, ast: ast)
      assert_issue(issues, message: ~r/path traversal/i)
    end

    test "detects path concatenation with user input" do
      ast = binop(:string, :<>, literal_string("/uploads/", line: 7), var("filename"), line: 7)

      issues = run_check(Security.PathTraversal, ast: ast)
      assert_issue(issues, category: :security)
    end

    test "ignores file operations with literal paths" do
      ast = call("File.read", [literal_string("config/app.json")], line: 1)
      issues = run_check(Security.PathTraversal, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── SSRFVulnerability ──────────────────────────────────────────────

  describe "SSRFVulnerability" do
    test "detects HTTP get with user-controlled URL variable" do
      ast = call("HTTPoison.get", [var("url")], line: 20)
      issues = run_check(Security.SSRFVulnerability, ast: ast)
      assert_issue(issues, message: ~r/SSRF/)
    end

    test "detects URL concatenation with user input" do
      ast =
        binop(:string, :<>, literal_string("https://api.example.com/"), var("user_endpoint"),
          line: 5
        )

      issues = run_check(Security.SSRFVulnerability, ast: ast)
      assert_issue(issues, category: :security)
    end

    test "ignores HTTP calls with literal URLs" do
      ast = call("HTTPoison.get", [literal_string("https://api.internal.com/health")], line: 1)
      issues = run_check(Security.SSRFVulnerability, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── SensitiveDataExposure ──────────────────────────────────────────

  describe "SensitiveDataExposure" do
    test "detects logging of password variable" do
      ast = call("logger.info", [var("password")], line: 9)
      issues = run_check(Security.SensitiveDataExposure, ast: ast)
      assert_issue(issues, message: ~r/sensitive/i)
    end

    test "detects logging of token variable" do
      ast = call("console.log", [var("api_token")], line: 3)
      issues = run_check(Security.SensitiveDataExposure, ast: ast)
      assert_issue(issues, category: :security)
    end

    test "ignores logging of non-sensitive variables" do
      ast = call("logger.info", [var("count")], line: 1)
      issues = run_check(Security.SensitiveDataExposure, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── TOCTOU ─────────────────────────────────────────────────────────

  describe "TOCTOU" do
    test "detects File.exists? followed by File.read" do
      ast =
        block([
          call("File.exists?", [var("path")], line: 5),
          call("File.read", [var("path")], line: 6)
        ])

      issues = run_check(Security.TOCTOU, ast: ast)
      assert_issue(issues, message: ~r/TOCTOU|time-of-check/i)
    end

    test "ignores standalone file existence check" do
      ast = call("File.exists?", [var("path")], line: 5)
      issues = run_check(Security.TOCTOU, ast: ast)
      assert_no_issues(issues)
    end
  end
end
