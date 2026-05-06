# Ubicloud Reviewer Playbook

_Generated from 2000 PR review comments. Last updated: 2026-05-07._

## How to use this playbook

You are reviewing changes to the ubicloud repository. For each rule below, check whether the diff violates it. When you flag an issue, cite the rule number and link to one of the example PRs.

## Rules

### R1. Don't mock database access in specs
**Rule:** In specs, create real model objects (and back Strands with real subjects via `Strand.create_with_id(model, ...)`) instead of mocking dataset/model methods or stubbing database calls.
**Why:** Mocked DB tests pass while production breaks; they also mask issues like aborted transactions caused by failed queries inside a label, and force unverified doubles.
**How to spot:** `allow(...).to receive(:dataset)`, `allow(SomeModel).to receive(:where)`, `allow(nx).to receive(:something)` for things you could change by mutating real records, or `let(:st) { instance_double(Strand, ...) }` instead of a real strand.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #5290](https://github.com/ubicloud/ubicloud/pull/5290)

### R2. Use `Strand.create_with_id(model, ...)` and pass model instances
**Rule:** Use `create_with_id` with a Sequel::Model first argument when creating a Strand for a known subject; use plain `create` with no block for plain row creation. Don't pair `Klass.generate_uuid` with `create { |x| x.id = ... }`.
**Why:** Eliminates `instance_variable_set(:@frame, nil)` workarounds in specs, lets the nexus look up the real subject, and keeps the idiom uniform across the codebase.
**How to spot:** `SomeModel.create { |s| s.id = SomeModel.generate_uuid }`, or test files setting `let(:st) { instance_double(Strand) }` while later mocking `nx.subject`.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4987](https://github.com/ubicloud/ubicloud/pull/4987), [PR #5001](https://github.com/ubicloud/ubicloud/pull/5001)

### R3. Use `refresh_frame(nx, new_values: {...})` instead of poking `@frame`
**Rule:** When a spec needs to change the strand frame, call `refresh_frame` rather than `nx.instance_variable_set(:@frame, nil)` or similar.
**Why:** Goes through the real loading path and keeps the spec resilient to internal changes.
**How to spot:** `instance_variable_set(:@frame, ...)` or `nx.instance_variable_set(:@strand, ...)` in specs.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818)

### R4. Don't mock `Time.now`; assert `be_within`
**Rule:** Don't stub `Time.now`/`DateTime.now` in specs — assert that the persisted timestamp is `be_within(N).of(Time.now)`, or that `allocated_at` changed `from(nil)`.
**Why:** Time mocks couple specs to internals, often go unused once present, and obscure what behavior is being verified.
**How to spot:** `allow(Time).to receive(:now)` or `Timecop.freeze` in new specs.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818)

### R5. Add an explicit `nil` in empty rescue blocks
**Rule:** When you swallow an exception, the rescue body must contain `nil` (with a brief comment explaining what was already-deleted/already-handled), not be empty.
**Why:** Branch-coverage testing fails when the rescue clause has no executable line, ensuring the path is exercised.
**How to spot:** `rescue Foo::NotFoundError\nend` with no body, especially on cloud-API destroy paths.
**Examples:** [PR #4809](https://github.com/ubicloud/ubicloud/pull/4809), [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4829](https://github.com/ubicloud/ubicloud/pull/4829), [PR #5105](https://github.com/ubicloud/ubicloud/pull/5105)

### R6. Rescue the smallest, most specific exception class
**Rule:** Don't use bare `rescue` or `rescue StandardError` around large blocks; rescue the specific exception classes you expect, around the smallest block where they can occur.
**Why:** Broad rescues hide typos and unrelated regressions for days/weeks. Bare rescues in templates and methods are particularly hard to test.
**How to spot:** Bare `rescue` (no class), `rescue => e` around 5+ lines, or rescuing `Google::Apis::ClientError`/`RuntimeError` when a narrower class exists.
**Examples:** [PR #4779](https://github.com/ubicloud/ubicloud/pull/4779), [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4856](https://github.com/ubicloud/ubicloud/pull/4856)

### R7. Avoid N+1 queries; batch via single query, eager loading, or `Semaphore.incr(ids, ...)`
**Rule:** Don't run a query inside a loop over an association. Use eager loading, `Semaphore.incr(dataset_or_ids, "name")`, `Strand.import`, or a single UNION/JOIN query.
**Why:** N+1 patterns repeatedly slip in (especially in semaphore increments and association walks); they hurt latency and DB load at scale.
**How to spot:** `xs.each { |x| Semaphore.incr([x.id], ...) }`, `xs.map { |x| Model.where(...).first }`, `each` loops that issue per-row updates/inserts.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #5091](https://github.com/ubicloud/ubicloud/pull/5091), [PR #5145](https://github.com/ubicloud/ubicloud/pull/5145), [PR #5238](https://github.com/ubicloud/ubicloud/pull/5238), [PR #5290](https://github.com/ubicloud/ubicloud/pull/5290)

### R8. Prefer `eager` over `eager_graph` when not filtering/ordering on the joined table
**Rule:** Use `eager [:assoc]` for plain preloads; reserve `eager_graph` for queries that filter or order by joined columns.
**Why:** `eager_graph` adds joins and complicates the query unnecessarily.
**How to spot:** `eager_graph [:assoc]` followed by no `where`/`order` referencing that association's columns.
**Examples:** [PR #4795](https://github.com/ubicloud/ubicloud/pull/4795), [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818)

### R9. Use `r`/argv arrays for external commands, never backticks or shell strings
**Rule:** In rhizome and any code calling external programs, use the `r` helper. Pass separate arguments (argv) so a shell isn't invoked. Never use backticks; never use `shellescape`/`shelljoin` when you could pass argv.
**Why:** Backticks silently swallow non-zero exits. Shell interpolation (especially inside `sudo`) is a command-injection risk and tends to be brittle.
**How to spot:** `` `cmd #{var}` ``, `r "cmd #{var}"` (single-string form with interpolation), `system "..."`, or `r("...".shellescape)`.
**Examples:** [PR #4779](https://github.com/ubicloud/ubicloud/pull/4779), [PR #4826](https://github.com/ubicloud/ubicloud/pull/4826), [PR #4895](https://github.com/ubicloud/ubicloud/pull/4895), [PR #5145](https://github.com/ubicloud/ubicloud/pull/5145), [PR #5290](https://github.com/ubicloud/ubicloud/pull/5290)

### R10. Use strict `Integer(s, 10)` instead of `String#to_i`
**Rule:** Convert strings to integers with `Integer(s, 10)` (with explicit base) when the input must be numeric, especially before interpolation into commands or sensitive logic.
**Why:** `"oops".to_i` silently returns `0`. Strict conversion catches garbage at the boundary instead of producing wrong behavior downstream.
**How to spot:** `ARGV[0].to_i`, `params["x"].to_i`, `annotations["count"].to_i`, anywhere user/external input becomes a number.
**Examples:** [PR #4779](https://github.com/ubicloud/ubicloud/pull/4779), [PR #4834](https://github.com/ubicloud/ubicloud/pull/4834), [PR #4870](https://github.com/ubicloud/ubicloud/pull/4870), [PR #5025](https://github.com/ubicloud/ubicloud/pull/5025)

### R11. Use `Process.clock_gettime(Process::CLOCK_MONOTONIC)` for elapsed-time deltas
**Rule:** When measuring durations between two points in the same process, use the monotonic clock, not `Time.now`.
**Why:** Wall-clock time can jump; the monotonic clock can't. It's also ~3× faster.
**How to spot:** `started = Time.now; ...; elapsed = Time.now - started` in new code.
**Examples:** [PR #4896](https://github.com/ubicloud/ubicloud/pull/4896)

### R12. Migrations: one query per `no_transaction`, `CONCURRENTLY` for indexes on existing tables, `NOT VALID` + later `VALIDATE`
**Rule:** A `no_transaction` migration must contain a single change. Add indexes on existing tables with `CONCURRENTLY` (in their own `no_transaction` migration). Add new constraints with `NOT VALID`, then validate in a follow-up migration. Bare `run "..."` to dodge rubocop is a smell.
**Why:** Partial application of multi-step `no_transaction` migrations cannot be retried. Validating a new constraint synchronously takes an exclusive table lock.
**How to spot:** `no_transaction` blocks with multiple operations; `add_index` (without CONCURRENTLY) on a long-lived table; `add_constraint`/`add_foreign_key` (without `not_valid: true`) on a long-lived table; `run "CREATE INDEX ..."` to bypass linting.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #5024](https://github.com/ubicloud/ubicloud/pull/5024)

### R13. Keep migrations and models in separate commits with the schema.cache update
**Rule:** Migrations (and the resulting `schema.cache` + model annotation updates) belong in their own commit, separate from new model code or routes that use the new columns. Always commit the regenerated `schema.cache` with the migration.
**Why:** Lets reviewers verify the schema delta in isolation and avoids broken intermediate states during deploy.
**How to spot:** A single commit that touches `migrate/`, `model/*.rb` annotations, and brand-new business logic together; or a migration commit that doesn't include `schema.cache`.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #5015](https://github.com/ubicloud/ubicloud/pull/5015), [PR #5145](https://github.com/ubicloud/ubicloud/pull/5145)

### R14. Web process must not SSH to resources or connect to customer databases
**Rule:** New web/admin code must not open SSH connections or direct DB connections to customer resources. If you need data from those resources for display, have the health monitor (or similar prog) record it in a database table, and have the web process read from that table.
**Why:** Long-term goal is to remove the web process's ability to reach customer infrastructure; adding more such code increases blast radius and reverses the direction of travel.
**How to spot:** New `sshable.cmd`/`ssh` calls or `PG.connect`/`Sequel.connect` in `routes/`, `clover_admin*.rb`, or anything in `views/`.
**Examples:** [PR #4779](https://github.com/ubicloud/ubicloud/pull/4779)

### R15. Admin site CSP: no inline styles, no inline `<svg>`/`<script>` without a nonce
**Rule:** The admin site's CSP forbids inline styles. Use class attributes and the admin stylesheet. For inline svg/script, require a `nonce` argument on the template and use `content_security_policy.add_img_src [:nonce, nonce_value]` (use one nonce per request, not per element). Templates rendered with locals must declare them: `<%# locals: (obj:) %>`.
**Why:** Without nonces, inline content is blocked. CSP violations are easy to miss locally.
**How to spot:** New `<svg ...>` or `style="..."` attributes in `views/` (especially admin), templates without an explicit `locals:` directive, or per-element nonces.
**Examples:** [PR #4779](https://github.com/ubicloud/ubicloud/pull/4779)

### R16. DRY duplicated logic into a method, module, or shared helper
**Rule:** When the same block of logic appears in multiple labels, progs, or specs (especially: GCP-op polling, error handling, sort/match patterns, semaphore reaping), extract it into a method or shared module.
**Why:** Recurring duplication accumulates drift; a shared method keeps cross-prog behavior consistent.
**How to spot:** Same `def` body in two progs; same 5-line sort/compare expression repeated; near-identical `rescue` shapes across labels.
**Examples:** [PR #4768](https://github.com/ubicloud/ubicloud/pull/4768), [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818)

### R17. Audit logs go inside the same transaction as the change
**Rule:** Always call `audit_log` inside the same transaction that performs the change being audited; use specific action names matching the operation (e.g., `add_cert_auth_user`, not just `update`).
**Why:** Logging outside the transaction means a rolled-back change can leave a phantom audit entry, or a successful change can be missed if the audit insert fails.
**How to spot:** `audit_log(...)` outside the surrounding `DB.transaction` block, or before the `update`/`create` it's auditing.
**Examples:** [PR #4874](https://github.com/ubicloud/ubicloud/pull/4874), [PR #5176](https://github.com/ubicloud/ubicloud/pull/5176)

### R18. Concurrent updates need transactions and conflict-aware queries
**Rule:** Mutations vulnerable to races (two requests adding/removing the same item, two strands creating the same cloud resource) must run in a transaction with idempotent SQL — typically a conditional `update` (e.g., `exclude(...).update(...)`), `INSERT ... ON CONFLICT`, or insert-fail-rescue patterns. A label is already inside a transaction, so a failing query aborts the rest.
**Why:** Read-modify-write at the Ruby level loses updates and produces inconsistent state. After a failed query inside a label/transaction, follow-up queries silently fail.
**How to spot:** `read; mutate in Ruby; write` flows; rescues that try to repair after a query already failed inside a label without a savepoint; jsonb concat without a `WHERE NOT contains` guard.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4874](https://github.com/ubicloud/ubicloud/pull/4874)

### R19. Don't sync-wait for cloud operations from a prog; use an async wait label
**Rule:** Never block a strand on a synchronous wait for an async cloud operation. Save the operation handle, hop to a `wait_*` label, and `nap` until it's done.
**Why:** Sync waits hold up the strand pool and break the cooperative scheduling model.
**How to spot:** `op.wait_until_done!`, `loop { sleep ...; break if op.done? }`, or any `sleep`/blocking poll inside a prog label.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818)

### R20. Insert-first when the resource usually doesn't exist; rescue conflict to recover
**Rule:** When creating a cloud resource that is unlikely to already exist, attempt the insert first and rescue an "already exists" error to fetch the existing one — rather than the get-fail-create-fail-get pattern.
**Why:** Get-first wastes API calls in the common path and complicates the rescue. Insert-first matches the actual lifecycle.
**How to spot:** `existing = client.get(...) rescue nil; existing || client.create(...)` for resources we ourselves create.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818)

### R21. Use `instance_double(Class, ...)` over `double(...)`
**Rule:** Use `instance_double` (with the actual class) when you must mock; reserve plain `double` for cases where the class genuinely isn't known, with a comment explaining why. Better still, use the real object.
**Why:** Verifying doubles catch API drift; plain doubles silently accept stale interfaces and miss production breakage.
**How to spot:** `double("name")` or `double(method: ...)` in specs for objects whose class is known.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818)

### R22. Avoid `allow` for must-call assertions and don't use `not_to receive` with arguments
**Rule:** In specs that test a single behavior, prefer `expect(...).to receive(...)` over `allow`. Push `to receive(...)` to the lowest call site (with arguments). Push `not_to receive` to the highest-level method (omit arguments to avoid false negatives if argument shape changes).
**Why:** `allow` doesn't fail when the call goes missing; `not_to receive(:foo, args)` can silently pass if the args change.
**How to spot:** `allow(Clog).to receive(:emit)` in a single-behavior spec; `not_to receive(:something).with(specific_args)`.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818)

### R23. Prefer `change { ... }.from(X).to(Y)` and `expect(record.exists?)` for state checks
**Rule:** Use `change { obj.reload.field }.from(X).to(Y)` (over `by(N)`) for clarity, and `expect(record.exists?).to be false` (over reloading and checking nil) for destruction checks.
**Why:** `from`/`to` document the expected pre- and post-state; `exists?` cleanly verifies a row is gone without raising.
**How to spot:** `change(Model, :count).by(1)`, `expect { record.reload }.to raise_error(...)`.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818)

### R24. `Clog.emit` expectations should `and_call_original`
**Rule:** When asserting `Clog.emit` was called, append `.and_call_original` so the actual log path is exercised by the spec.
**Why:** Bare expectations stub out the emit, so coverage/format issues in the real call path go untested.
**How to spot:** `expect(Clog).to receive(:emit).with(...)` without `.and_call_original`.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818)

### R25. Avoid unnecessary allocations: prefer `Set`, in-place mutators, and `.freeze` on literals
**Rule:** Use `Set.new(coll, &:attr)` / `coll.to_set(&:attr)` for membership tests over arrays; use `map!`/`sort!`/`sort_by!` when the receiver is already a fresh array; freeze constant literals (especially Ruby 3.4+ array literals) used inside `include?`. Avoid creating an intermediate `dup` when one local will do.
**Why:** Hot paths repeat per request/strand; small allocations add up. `Set` membership is O(1) vs O(N).
**How to spot:** `xs.include?(y)` over a long array literal in a hot path; `xs.map { ... }.sort` where `xs` is freshly built; `["a", "b"]` literal in a `include?` call without `.freeze`.
**Examples:** [PR #4257](https://github.com/ubicloud/ubicloud/pull/4257), [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818)

### R26. Don't introduce top-level constants outside their dedicated file
**Rule:** Implementation-detail constants belong nested inside the class that owns them (e.g., `Page::Client`), not as top-level constants. Use class names (strings) instead of class references in lookup tables to avoid forcing autoload.
**Why:** Top-level constants don't reload cleanly in development; constant references in lookup hashes force autoloading and break reload semantics.
**How to spot:** New top-level `class`/`module`/constant added at the bottom of a file dedicated to a different class; lookup hashes keyed by `SomeClass` instead of `"SomeClass"`.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4863](https://github.com/ubicloud/ubicloud/pull/4863)
