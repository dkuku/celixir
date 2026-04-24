defmodule Celixir.CelFilesIntegrationTest do
  use ExUnit.Case

  @cel_dir Path.join(__DIR__, "cel_files")

  defp load_eval(filename, bindings) do
    path = Path.join(@cel_dir, filename)
    program = Celixir.load_file!(path)
    Celixir.Program.eval(program, bindings)
  end

  # ---------------------------------------------------------------------------
  # access_policy.cel
  # Allows GET/HEAD unconditionally; POST only for admin/editor on /api/ paths.
  # ---------------------------------------------------------------------------

  describe "access_policy.cel" do
    test "GET is always allowed" do
      bindings = %{
        request: %{"method" => "GET", "auth" => %{"role" => "guest"}, "path" => "/public/index"}
      }

      assert {:ok, true} = load_eval("access_policy.cel", bindings)
    end

    test "HEAD is always allowed" do
      bindings = %{
        request: %{"method" => "HEAD", "auth" => %{"role" => "guest"}, "path" => "/api/users"}
      }

      assert {:ok, true} = load_eval("access_policy.cel", bindings)
    end

    test "POST from admin to /api/ path is allowed" do
      bindings = %{
        request: %{"method" => "POST", "auth" => %{"role" => "admin"}, "path" => "/api/users"}
      }

      assert {:ok, true} = load_eval("access_policy.cel", bindings)
    end

    test "POST from editor to /api/ path is allowed" do
      bindings = %{
        request: %{"method" => "POST", "auth" => %{"role" => "editor"}, "path" => "/api/posts"}
      }

      assert {:ok, true} = load_eval("access_policy.cel", bindings)
    end

    test "POST from guest is denied" do
      bindings = %{
        request: %{"method" => "POST", "auth" => %{"role" => "guest"}, "path" => "/api/users"}
      }

      assert {:ok, false} = load_eval("access_policy.cel", bindings)
    end

    test "POST from admin to non-api path is denied" do
      bindings = %{
        request: %{"method" => "POST", "auth" => %{"role" => "admin"}, "path" => "/internal/data"}
      }

      assert {:ok, false} = load_eval("access_policy.cel", bindings)
    end

    test "DELETE is always denied" do
      bindings = %{
        request: %{"method" => "DELETE", "auth" => %{"role" => "admin"}, "path" => "/api/users"}
      }

      assert {:ok, false} = load_eval("access_policy.cel", bindings)
    end
  end

  # ---------------------------------------------------------------------------
  # grade_report.cel
  # Filters passing scores (>= 60), maps to letter grades, sorts alphabetically.
  # ---------------------------------------------------------------------------

  describe "grade_report.cel" do
    test "returns sorted letter grades for a mixed set of scores" do
      assert {:ok, ["A", "B", "C", "D"]} =
               load_eval("grade_report.cel", %{scores: [75, 92, 68, 85, 55]})
    end

    test "empty list when all scores below 60" do
      assert {:ok, []} = load_eval("grade_report.cel", %{scores: [10, 30, 55]})
    end

    test "single A for perfect score" do
      assert {:ok, ["A"]} = load_eval("grade_report.cel", %{scores: [100]})
    end

    test "multiple As are deduplicated by sort (not distinct, but sort is stable)" do
      {:ok, result} = load_eval("grade_report.cel", %{scores: [91, 95, 98]})
      assert result == ["A", "A", "A"]
    end
  end

  # ---------------------------------------------------------------------------
  # text_processing.cel
  # Trims, splits, filters short words, uppercases, joins with comma.
  # ---------------------------------------------------------------------------

  describe "text_processing.cel" do
    test "filters words <= 3 chars and uppercases the rest" do
      assert {:ok, "QUICK, BROWN"} =
               load_eval("text_processing.cel", %{message: "  the quick brown fox  "})
    end

    test "trims leading and trailing whitespace before splitting" do
      assert {:ok, "HELLO, WORLD"} =
               load_eval("text_processing.cel", %{message: "  hello world  "})
    end

    test "returns empty string when all words are short" do
      assert {:ok, ""} = load_eval("text_processing.cel", %{message: "a bb cc"})
    end

    test "single long word produces single entry" do
      assert {:ok, "INTEGRATION"} =
               load_eval("text_processing.cel", %{message: "integration"})
    end
  end

  # ---------------------------------------------------------------------------
  # math_computation.cel
  # Computes ceil(sqrt(abs(x² - y²))).
  # ---------------------------------------------------------------------------

  describe "math_computation.cel" do
    test "pythagorean triple 5,3 gives 4.0" do
      assert {:ok, 4.0} = load_eval("math_computation.cel", %{x: 5, y: 3})
    end

    test "equal values give 0.0" do
      assert {:ok, result} = load_eval("math_computation.cel", %{x: 7, y: 7})
      assert result == 0.0
    end

    test "ceil rounds up non-integer sqrt" do
      # abs(4² - 3²) = 7, sqrt(7) ≈ 2.645, ceil = 3.0
      assert {:ok, 3.0} = load_eval("math_computation.cel", %{x: 4, y: 3})
    end

    test "negative difference is handled by abs" do
      # Same result regardless of which is larger
      assert {:ok, result_a} = load_eval("math_computation.cel", %{x: 5, y: 3})
      assert {:ok, result_b} = load_eval("math_computation.cel", %{x: 3, y: 5})
      assert result_a == result_b
    end
  end

  # ---------------------------------------------------------------------------
  # encode_check.cel
  # Verifies base64 round-trip and that encoded output is non-empty.
  # ---------------------------------------------------------------------------

  describe "encode_check.cel" do
    test "round-trip decode(encode(data)) == data" do
      assert {:ok, true} = load_eval("encode_check.cel", %{data: "Hello, CEL!"})
    end

    test "works with empty string" do
      assert {:ok, true} = load_eval("encode_check.cel", %{data: ""})
    end

    test "works with binary data containing special characters" do
      assert {:ok, true} = load_eval("encode_check.cel", %{data: "line1\nline2\ttab"})
    end

    test "works with unicode content" do
      assert {:ok, true} = load_eval("encode_check.cel", %{data: "café résumé"})
    end
  end

  # ---------------------------------------------------------------------------
  # config_validation.cel
  # Validates host presence, port range, and environment name.
  # ---------------------------------------------------------------------------

  describe "config_validation.cel" do
    test "valid development config passes" do
      assert {:ok, true} =
               load_eval("config_validation.cel", %{
                 config: %{"host" => "localhost", "port" => 8080, "env" => "development"}
               })
    end

    test "valid production config passes" do
      assert {:ok, true} =
               load_eval("config_validation.cel", %{
                 config: %{"host" => "prod.example.com", "port" => 8443, "env" => "production"}
               })
    end

    test "port below 1024 fails" do
      assert {:ok, false} =
               load_eval("config_validation.cel", %{
                 config: %{"host" => "localhost", "port" => 80, "env" => "development"}
               })
    end

    test "port above 65535 fails" do
      assert {:ok, false} =
               load_eval("config_validation.cel", %{
                 config: %{"host" => "localhost", "port" => 70_000, "env" => "development"}
               })
    end

    test "unknown env value fails" do
      assert {:ok, false} =
               load_eval("config_validation.cel", %{
                 config: %{"host" => "localhost", "port" => 8080, "env" => "test"}
               })
    end
  end

  # ---------------------------------------------------------------------------
  # nested_aggregation.cel
  # Filters active users, extracts scores, checks all meet minimum.
  # ---------------------------------------------------------------------------

  describe "nested_aggregation.cel" do
    test "all active users above threshold returns true" do
      bindings = %{
        users: [
          %{"active" => true, "score" => 85},
          %{"active" => false, "score" => 30},
          %{"active" => true, "score" => 92}
        ],
        min_score: 80
      }

      assert {:ok, true} = load_eval("nested_aggregation.cel", bindings)
    end

    test "one active user below threshold returns false" do
      bindings = %{
        users: [
          %{"active" => true, "score" => 85},
          %{"active" => true, "score" => 70}
        ],
        min_score: 80
      }

      assert {:ok, false} = load_eval("nested_aggregation.cel", bindings)
    end

    test "no active users returns true (vacuously)" do
      bindings = %{
        users: [%{"active" => false, "score" => 10}],
        min_score: 80
      }

      assert {:ok, true} = load_eval("nested_aggregation.cel", bindings)
    end

    test "empty user list returns true (vacuously)" do
      assert {:ok, true} = load_eval("nested_aggregation.cel", %{users: [], min_score: 80})
    end
  end

  # ---------------------------------------------------------------------------
  # rate_limit.cel
  # Allows requests within max_rate; premium tier bypasses the free tier limit.
  # ---------------------------------------------------------------------------

  describe "rate_limit.cel" do
    test "premium tier under max_rate is allowed" do
      bindings = %{requests_per_minute: 50, max_rate: 100, tier: "premium", free_tier_limit: 30}
      assert {:ok, true} = load_eval("rate_limit.cel", bindings)
    end

    test "free tier under free limit is allowed" do
      bindings = %{requests_per_minute: 20, max_rate: 100, tier: "free", free_tier_limit: 30}
      assert {:ok, true} = load_eval("rate_limit.cel", bindings)
    end

    test "free tier over free limit is denied" do
      bindings = %{requests_per_minute: 50, max_rate: 100, tier: "free", free_tier_limit: 30}
      assert {:ok, false} = load_eval("rate_limit.cel", bindings)
    end

    test "any tier over max_rate is denied" do
      bindings = %{requests_per_minute: 150, max_rate: 100, tier: "premium", free_tier_limit: 30}
      assert {:ok, false} = load_eval("rate_limit.cel", bindings)
    end

    test "premium tier over free limit but under max_rate is allowed" do
      bindings = %{requests_per_minute: 80, max_rate: 100, tier: "premium", free_tier_limit: 30}
      assert {:ok, true} = load_eval("rate_limit.cel", bindings)
    end
  end

  # ---------------------------------------------------------------------------
  # regex_pipeline.cel
  # Checks that an IP address exists in the log line and HTTP version is 1.1.
  # ---------------------------------------------------------------------------

  describe "regex_pipeline.cel" do
    test "valid HTTP/1.1 log line with IP passes" do
      bindings = %{log_line: "192.168.1.1 - GET /path HTTP/1.1 200"}
      assert {:ok, true} = load_eval("regex_pipeline.cel", bindings)
    end

    test "HTTP/1.0 log line fails version check" do
      bindings = %{log_line: "10.0.0.1 - GET /path HTTP/1.0 200"}
      assert {:ok, false} = load_eval("regex_pipeline.cel", bindings)
    end

    test "log line without IP fails" do
      bindings = %{log_line: "localhost - GET /path HTTP/1.1 200"}
      assert {:ok, false} = load_eval("regex_pipeline.cel", bindings)
    end
  end

  # ---------------------------------------------------------------------------
  # combined_pipeline.cel
  # Filters active users above threshold, normalises names, deduplicates, sorts.
  # ---------------------------------------------------------------------------

  describe "combined_pipeline.cel" do
    test "filters, normalises, deduplicates and sorts names" do
      bindings = %{
        items: [
          %{"active" => true, "score" => 85, "name" => " Alice "},
          %{"active" => false, "score" => 90, "name" => " Bob "},
          %{"active" => true, "score" => 78, "name" => " Charlie "},
          %{"active" => true, "score" => 65, "name" => " Dave "}
        ],
        threshold: 75
      }

      assert {:ok, ["alice", "charlie"]} = load_eval("combined_pipeline.cel", bindings)
    end

    test "duplicate names after normalisation are collapsed" do
      bindings = %{
        items: [
          %{"active" => true, "score" => 90, "name" => " Alice "},
          %{"active" => true, "score" => 88, "name" => "ALICE"}
        ],
        threshold: 80
      }

      assert {:ok, ["alice"]} = load_eval("combined_pipeline.cel", bindings)
    end

    test "empty result when no items pass filter" do
      bindings = %{
        items: [
          %{"active" => false, "score" => 90, "name" => "Bob"},
          %{"active" => true, "score" => 50, "name" => "Carol"}
        ],
        threshold: 75
      }

      assert {:ok, []} = load_eval("combined_pipeline.cel", bindings)
    end
  end
end
