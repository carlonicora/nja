# Suite for scripts/nja-lint.sh: the BLOCKING raw-records rule and
# documented file-level exceptions. Sourced by run.sh.
LINT="$NJA_SCRIPTS_DIR/nja-lint.sh"

lint_repo="$(t_mkrepo)"
lint_exc="$(cd "$(mktemp -d -t nja-exc)" && pwd -P)"
mkdir -p "$lint_exc/backend" "$lint_repo/apps/api/src/features/report/repositories"
cat > "$lint_exc/backend/03-repositories.md" <<'MD'
# Repositories
<!-- nja-lint-exception: "cross-tenant administrative read repository" files=*.admin.repository.ts rules=raw-neo4j-records,raw-neo4j-query,manual-query-no-company-scope -->
MD
export NJA_LINT_EXCEPTIONS_DIR="$lint_exc"
lint_dir="$lint_repo/apps/api/src/features/report/repositories"

# 1. raw records are BLOCKING in every shape; comment lines are ignored.
cat > "$lint_dir/report.repository.ts" <<'TS'
export class ReportRepository {
  async a() { const result = await this.neo4j.read(q); return result.records[0]; }
  async b() { return result.records; }
  async c() { return (result.records as any[]).map((r) => r); }
  async d() { return [...a.records, ...b.records]; }
  // result.records is never used like this
   * see result.records in the docs
}
TS
lint_out="$(cd "$lint_repo" && bash "$LINT" apps/api/src/features/report/repositories/report.repository.ts 2>&1)"
t_assert_exit 2 "raw .records use exits 2" -- bash "$LINT" "$lint_dir/report.repository.ts"
t_assert_contains "$lint_out" "report.repository.ts:2 [BLOCKING] raw-neo4j-records" "records[0] is blocking"
t_assert_contains "$lint_out" "report.repository.ts:3 [BLOCKING] raw-neo4j-records" "return result.records is blocking"
t_assert_contains "$lint_out" "report.repository.ts:4 [BLOCKING] raw-neo4j-records" "(records as any[]).map is blocking"
t_assert_contains "$lint_out" "report.repository.ts:5 [BLOCKING] raw-neo4j-records" "spread records is blocking"
t_assert_not_contains "$lint_out" "report.repository.ts:6 " "// comment line is ignored"
t_assert_not_contains "$lint_out" "report.repository.ts:7 " "* comment line is ignored"
t_assert_contains "$lint_out" "references/backend/03-repositories.md" "doc pointer is the repositories reference"

# 2. a documented exception on a matching file skips the listed rules.
cat > "$lint_dir/report.admin.repository.ts" <<'TS'
// nja-lint-ignore-file: cross-tenant administrative read repository.
export class ReportAdminRepository {
  async a() { const result = await this.neo4j.read(`MATCH (c:Company) RETURN c`); return result.records; }
}
TS
lint_out="$(cd "$lint_repo" && bash "$LINT" apps/api/src/features/report/repositories/report.admin.repository.ts 2>&1)"
t_assert_exit 0 "documented exception passes" -- bash "$LINT" "$lint_dir/report.admin.repository.ts"
t_assert_not_contains "$lint_out" "raw-neo4j-records" "listed rule raw-neo4j-records is skipped"
t_assert_not_contains "$lint_out" "manual-query-no-company-scope" "listed rule manual-query-no-company-scope is skipped"
t_assert_not_contains "$lint_out" "raw-neo4j-query" "listed rule raw-neo4j-query is skipped"

# 2b. the exception skips only the listed rules.
cat > "$lint_dir/other.admin.repository.ts" <<'TS'
// nja-lint-ignore-file: cross-tenant administrative read repository
export class OtherAdminRepository {
  q = `MATCH (n) RETURN n SKIP $skip`;
}
TS
lint_out="$(cd "$lint_repo" && bash "$LINT" apps/api/src/features/report/repositories/other.admin.repository.ts 2>&1)"
t_assert_contains "$lint_out" "[BLOCKING] manual-pagination" "unlisted rules still fire under an exception"
t_assert_not_contains "$lint_out" "undocumented-file-exception" "header without trailing period is accepted"

# 3. an undocumented header blocks at the header line.
cat > "$lint_dir/clean.repository.ts" <<'TS'
// a clean file
// nja-lint-ignore-file: because I said so.
export class CleanRepository {}
TS
lint_out="$(cd "$lint_repo" && bash "$LINT" apps/api/src/features/report/repositories/clean.repository.ts 2>&1)"
t_assert_exit 2 "undocumented header exits 2" -- bash "$LINT" "$lint_dir/clean.repository.ts"
t_assert_contains "$lint_out" "clean.repository.ts:2 [BLOCKING] undocumented-file-exception" "undocumented header is reported at its line"
t_assert_contains "$lint_out" "must be documented in the nja-architecture skill" "message names the skill"

# 4. a documented name on a file outside its glob blocks.
cat > "$lint_dir/report2.repository.ts" <<'TS'
// nja-lint-ignore-file: cross-tenant administrative read repository.
export class Report2Repository { async a() { return result.records; } }
TS
lint_out="$(cd "$lint_repo" && bash "$LINT" apps/api/src/features/report/repositories/report2.repository.ts 2>&1)"
t_assert_contains "$lint_out" "report2.repository.ts:1 [BLOCKING] undocumented-file-exception" "glob mismatch blocks at the header"
t_assert_contains "$lint_out" "report2.repository.ts:2 [BLOCKING] raw-neo4j-records" "glob mismatch skips nothing"

# 4b. without any marker directory, the real header blocks.
lint_empty="$(cd "$(mktemp -d -t nja-exc-empty)" && pwd -P)"
lint_out="$(cd "$lint_repo" && NJA_LINT_EXCEPTIONS_DIR="$lint_empty" bash "$LINT" apps/api/src/features/report/repositories/report.admin.repository.ts 2>&1)"
t_assert_contains "$lint_out" "[BLOCKING] undocumented-file-exception" "no marker means the header blocks"

# 5. the per-line ignore still works.
cat > "$lint_dir/ignored.repository.ts" <<'TS'
export class IgnoredRepository {
  async a() { return result.records; } // nja-lint-ignore
}
TS
t_assert_exit 0 "per-line nja-lint-ignore still skips the line" -- bash "$LINT" "$lint_dir/ignored.repository.ts"

unset NJA_LINT_EXCEPTIONS_DIR
rm -rf "$lint_repo" "$lint_exc" "$lint_empty"
