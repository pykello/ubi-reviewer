# Ubicloud Reviewer Playbook

_Generated from 11263 PR review comments. Last updated: 2026-05-07._

## How to use this playbook

You are reviewing changes to the ubicloud repository. Walk **every** rule below and check whether the diff violates it. When you flag an issue, cite the rule number and link to one of the example PRs.

## Blocker

### R1. Don't sync-wait for cloud operations from a prog — Concurrency
**Severity:** blocker
**Rule:** Never block a strand on a synchronous wait for an async cloud operation. Save the operation handle and `hop` to a `wait_*` label that `nap`s until done.
**Why:** Sync waits hold up the strand pool and break the cooperative scheduling model. This is the most-cited concurrency mistake in the corpus.
**How to spot:** `op.wait_until_done!`, `loop { sleep ...; break if op.done? }`, or any `sleep`/blocking poll inside a prog label.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4476](https://github.com/ubicloud/ubicloud/pull/4476), [PR #4179](https://github.com/ubicloud/ubicloud/pull/4179), [PR #5290](https://github.com/ubicloud/ubicloud/pull/5290)

### R2. Concurrent updates need transactions and conflict-aware queries — Concurrency
**Severity:** blocker
**Rule:** Mutations vulnerable to races (two requests adding/removing the same item, two strands creating the same cloud resource) must run in a transaction with idempotent SQL — typically a conditional `update` (`exclude(...).update(...)`), `INSERT ... ON CONFLICT`, or insert-fail-rescue. A label is already in a transaction, so a failing query aborts the rest.
**Why:** Read-modify-write at the Ruby level loses updates and produces inconsistent state. After a failed query inside a label/transaction, follow-up queries silently fail.
**How to spot:** `read; mutate in Ruby; write` flows; rescues that try to repair after a query already failed inside a label without a savepoint; jsonb concat without a `WHERE NOT contains` guard; `update`s without a `where` guard on the prior state.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4874](https://github.com/ubicloud/ubicloud/pull/4874), [PR #1003](https://github.com/ubicloud/ubicloud/pull/1003), [PR #1583](https://github.com/ubicloud/ubicloud/pull/1583)

### R3. Avoid N+1 queries; batch via single query, eager loading, or `Semaphore.incr(ids, ...)` — Performance
**Severity:** blocker
**Rule:** Don't run a query inside a loop over an association. Use eager loading, `Semaphore.incr(dataset_or_ids, "name")`, `Strand.import`, or a single UNION/JOIN query.
**Why:** N+1 patterns repeatedly slip into semaphore increments, association walks, and view rendering; they hurt latency and DB load at scale and are flagged across dozens of PRs.
**How to spot:** `xs.each { |x| Semaphore.incr([x.id], ...) }`, `xs.map { |x| Model.where(...).first }`, `each` loops issuing per-row updates/inserts, ERB templates calling association methods inside a loop without preload.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #5145](https://github.com/ubicloud/ubicloud/pull/5145), [PR #5290](https://github.com/ubicloud/ubicloud/pull/5290), [PR #5238](https://github.com/ubicloud/ubicloud/pull/5238), [PR #5091](https://github.com/ubicloud/ubicloud/pull/5091)

### R4. Use `r`/argv arrays for external commands; never backticks or shell strings — Security
**Severity:** blocker
**Rule:** In rhizome and any code calling external programs, use the `r` helper. Pass separate arguments (argv) so a shell isn't invoked. Never use backticks; never use `shellescape`/`shelljoin` when you could pass argv.
**Why:** Backticks silently swallow non-zero exits. Shell interpolation (especially inside `sudo`) is a command-injection risk and is fragile around special characters.
**How to spot:** `` `cmd #{var}` ``, `r "cmd #{var}"` (single-string form with interpolation), `system "..."`, or `r("...".shellescape)`.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4779](https://github.com/ubicloud/ubicloud/pull/4779), [PR #4895](https://github.com/ubicloud/ubicloud/pull/4895), [PR #2598](https://github.com/ubicloud/ubicloud/pull/2598), [PR #5290](https://github.com/ubicloud/ubicloud/pull/5290)

### R5. Use strict `Integer(s, 10)` not `String#to_i` — Correctness
**Severity:** blocker
**Rule:** Convert strings to integers with `Integer(s, 10)` (with explicit base) when the input must be numeric, especially before interpolation into commands or sensitive logic.
**Why:** `"oops".to_i` silently returns `0`. Strict conversion catches garbage at the boundary instead of producing wrong behavior downstream.
**How to spot:** `ARGV[0].to_i`, `params["x"].to_i`, `annotations["count"].to_i` — anywhere user/external input becomes a number. Be skeptical of `to_i` on data that crosses a process or HTTP boundary.
**Examples:** [PR #4779](https://github.com/ubicloud/ubicloud/pull/4779), [PR #4834](https://github.com/ubicloud/ubicloud/pull/4834), [PR #4870](https://github.com/ubicloud/ubicloud/pull/4870), [PR #1244](https://github.com/ubicloud/ubicloud/pull/1244), [PR #5025](https://github.com/ubicloud/ubicloud/pull/5025)

### R6. Don't mock database access in specs; use real models — Testing rigor
**Severity:** blocker
**Rule:** Create real model objects (and back Strands with real subjects via `Strand.create_with_id(model, ...)`) instead of mocking dataset/model methods or stubbing database calls. When you must mock, use `instance_double(Class, ...)` not bare `double(...)`.
**Why:** Mocked DB tests pass while production breaks; they mask aborted-transaction bugs caused by failed queries inside a label and force unverified doubles. Verifying doubles catch API drift; plain doubles silently accept stale interfaces.
**How to spot:** `allow(...).to receive(:dataset)`, `allow(SomeModel).to receive(:where)`, `allow(nx).to receive(:something)` for things mutable via real records; `let(:st) { instance_double(Strand, ...) }` instead of a real strand; `double("name")` for objects whose class is known.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #5290](https://github.com/ubicloud/ubicloud/pull/5290), [PR #5262](https://github.com/ubicloud/ubicloud/pull/5262), [PR #4476](https://github.com/ubicloud/ubicloud/pull/4476), [PR #5024](https://github.com/ubicloud/ubicloud/pull/5024)

### R7. Use `Strand.create_with_id(model, ...)` for strands — Correctness
**Severity:** blocker
**Rule:** Use `Strand.create_with_id(subject_or_id, prog: ..., label: ...)` to create a Strand. Pass a Sequel::Model instance (not just an id) when the subject already exists, so the nexus can look it up. Never pair `Klass.generate_uuid` with `create { |x| x.id = ... }` for new code.
**Why:** Eliminates `instance_variable_set(:@frame, nil)` workarounds in specs, lets the nexus resolve the real subject, and keeps the idiom uniform across the codebase. Jeremy fixes this consistently across PRs.
**How to spot:** `SomeModel.create { |s| s.id = SomeModel.generate_uuid }`, `Strand.create(...) { |s| s.id = ... }`, or test files setting `let(:st) { instance_double(Strand) }` while later mocking `nx.subject`.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4987](https://github.com/ubicloud/ubicloud/pull/4987), [PR #5001](https://github.com/ubicloud/ubicloud/pull/5001), [PR #4376](https://github.com/ubicloud/ubicloud/pull/4376), [PR #4391](https://github.com/ubicloud/ubicloud/pull/4391)

### R8. Rescue the smallest, most specific exception class — Error handling
**Severity:** blocker
**Rule:** Don't use bare `rescue` or `rescue StandardError` around large blocks; rescue the specific exception classes you expect, around the smallest block where they can occur.
**Why:** Broad rescues hide typos and unrelated regressions for days/weeks. Bare rescues in templates and methods are particularly hard to test.
**How to spot:** Bare `rescue` (no class), `rescue => e` around 5+ lines, or rescuing `Google::Apis::ClientError`/`RuntimeError` when a narrower class exists.
**Examples:** [PR #4779](https://github.com/ubicloud/ubicloud/pull/4779), [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4856](https://github.com/ubicloud/ubicloud/pull/4856), [PR #4503](https://github.com/ubicloud/ubicloud/pull/4503)

### R9. Add an explicit `nil` (with comment) in empty rescue blocks — Error handling
**Severity:** blocker
**Rule:** When you swallow an exception, the rescue body must contain `nil` (with a brief comment explaining what was already-deleted/already-handled), not be empty.
**Why:** Branch-coverage testing fails when the rescue clause has no executable line, ensuring the path is actually exercised.
**How to spot:** `rescue Foo::NotFoundError\nend` with no body, especially on cloud-API destroy paths.
**Examples:** [PR #4809](https://github.com/ubicloud/ubicloud/pull/4809), [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4829](https://github.com/ubicloud/ubicloud/pull/4829), [PR #5105](https://github.com/ubicloud/ubicloud/pull/5105)

### R10. Migrations: one query per `no_transaction`, `CONCURRENTLY` for indexes, `NOT VALID` + `VALIDATE` — Database
**Severity:** blocker
**Rule:** A `no_transaction` migration must contain a single change. Add indexes on existing tables with `CONCURRENTLY` (in their own `no_transaction` migration). Add new constraints with `NOT VALID`, then validate in a follow-up migration. Bare `run "..."` to dodge rubocop is a smell.
**Why:** Partial application of multi-step `no_transaction` migrations cannot be retried. Validating a new constraint synchronously takes an exclusive table lock and stalls writes.
**How to spot:** `no_transaction` blocks with multiple operations; `add_index` (without CONCURRENTLY) on a long-lived table; `add_constraint`/`add_foreign_key` (without `not_valid: true`) on a long-lived table; `run "CREATE INDEX ..."` to bypass linting.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #5024](https://github.com/ubicloud/ubicloud/pull/5024), [PR #2901](https://github.com/ubicloud/ubicloud/pull/2901), [PR #4761](https://github.com/ubicloud/ubicloud/pull/4761)

### R11. Migrations must be reversible; pick `change` vs `up`/`down` correctly — Database
**Severity:** blocker
**Rule:** Use a `change` block only when Sequel can auto-reverse every operation. If the migration runs raw SQL via `run`, mutates a dataset, drops a column, or otherwise has an asymmetric reverse, write explicit `up` and `down` blocks (or use `add` if you intend the down to be a no-op). A `drop_column` cannot be `change`d (the type is unknown). A `commented-out up block` is a mistake.
**Why:** Irreversible migrations make rollback impossible at deploy time and surface as silent footguns.
**How to spot:** `change do ... run "..." ... end`, `change do ... drop_column ... end`, `change do ... DB[...].update(...) ... end`, commented-out reverse logic.
**Examples:** [PR #3854](https://github.com/ubicloud/ubicloud/pull/3854), [PR #3099](https://github.com/ubicloud/ubicloud/pull/3099), [PR #2367](https://github.com/ubicloud/ubicloud/pull/2367), [PR #2710](https://github.com/ubicloud/ubicloud/pull/2710), [PR #2718](https://github.com/ubicloud/ubicloud/pull/2718)

### R12. Audit logs go inside the same transaction as the change, with specific action names — Logging
**Severity:** blocker
**Rule:** Always call `audit_log` inside the same transaction that performs the change being audited. Use specific action names matching the operation (e.g., `add_cert_auth_user`, `remove_cert_auth_user`) and add them to the allowed audit actions list — not generic `update`.
**Why:** Logging outside the transaction means a rolled-back change can leave a phantom audit entry, or a successful change can be missed if the audit insert fails. Standardization (#4960) is in progress for action naming.
**How to spot:** `audit_log(...)` outside the surrounding `DB.transaction` block, before the `update`/`create` it's auditing, or with a generic action name like `"update"` when a specific verb fits.
**Examples:** [PR #4874](https://github.com/ubicloud/ubicloud/pull/4874), [PR #5176](https://github.com/ubicloud/ubicloud/pull/5176), [PR #3923](https://github.com/ubicloud/ubicloud/pull/3923), [PR #3979](https://github.com/ubicloud/ubicloud/pull/3979)

### R13. Web/admin process must not SSH to or DB-connect customer resources — Security
**Severity:** blocker
**Rule:** New web/admin code must not open SSH connections or direct DB connections to customer resources. If you need data from those resources for display, have the health monitor (or similar prog) record it in a database table, and have the web process read from that table.
**Why:** The long-term goal is to remove the web process's ability to reach customer infrastructure; adding more such code increases blast radius and reverses the direction of travel.
**How to spot:** New `sshable.cmd`/`ssh` calls or `PG.connect`/`Sequel.connect` in `routes/`, `clover_admin*.rb`, or anything in `views/`.
**Examples:** [PR #4779](https://github.com/ubicloud/ubicloud/pull/4779), [PR #2967](https://github.com/ubicloud/ubicloud/pull/2967), [PR #2979](https://github.com/ubicloud/ubicloud/pull/2979), [PR #4677](https://github.com/ubicloud/ubicloud/pull/4677)

### R14. Don't modify state in GET routes — API conventions
**Severity:** blocker
**Rule:** GET routes must be safe (no side-effects). State changes — model `update`s, `create`s, `audit_log`s — belong on POST/PATCH/DELETE.
**Why:** REST safety is a real constraint: caches, retries, monitors, and crawlers may all replay GETs. State changes inside GETs cause hard-to-diagnose duplications and security issues.
**How to spot:** `r.get` or `r.is do ... <model>.update(...) ... end`, `audit_log` invocations under a GET branch.
**Examples:** [PR #3853](https://github.com/ubicloud/ubicloud/pull/3853), [PR #3148](https://github.com/ubicloud/ubicloud/pull/3148), [PR #1779](https://github.com/ubicloud/ubicloud/pull/1779), [PR #3622](https://github.com/ubicloud/ubicloud/pull/3622)

### R15. Admin site CSP: nonces for inline content, no inline styles, declare template `locals:` — Security
**Severity:** blocker
**Rule:** The admin site's CSP forbids inline styles. Use class attributes and the admin stylesheet. For inline svg/script, require a `nonce` argument on the template and use `content_security_policy.add_img_src [:nonce, nonce_value]` (one nonce per request, not per element). Templates rendered with locals must declare them: `<%# locals: (obj:) %>`.
**Why:** Without nonces, inline content is blocked. CSP violations are easy to miss in development.
**How to spot:** New `<svg ...>` or `style="..."` attributes in `views/` (especially admin), templates without an explicit `locals:` directive, per-element nonces.
**Examples:** [PR #4779](https://github.com/ubicloud/ubicloud/pull/4779), [PR #4826](https://github.com/ubicloud/ubicloud/pull/4826), [PR #4494](https://github.com/ubicloud/ubicloud/pull/4494)

### R16. Migration + model changes go in their own commit with `schema.cache` — Process
**Severity:** blocker
**Rule:** Migrations (and the resulting `schema.cache` + model annotation updates) belong in their own commit, separate from new model code or routes that use the new columns. Always commit the regenerated `schema.cache` with the migration.
**Why:** Lets reviewers verify the schema delta in isolation and avoids broken intermediate states during deploy.
**How to spot:** A single commit that touches `migrate/`, `model/*.rb` annotations, and brand-new business logic together; or a migration commit that doesn't include `schema.cache`.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #5015](https://github.com/ubicloud/ubicloud/pull/5015), [PR #5145](https://github.com/ubicloud/ubicloud/pull/5145), [PR #2384](https://github.com/ubicloud/ubicloud/pull/2384)

### R17. Use `refresh_frame(nx, new_values: {...})` instead of poking `@frame`/`@strand` — Testing rigor
**Severity:** blocker
**Rule:** When a spec needs to change the strand frame, call `refresh_frame` rather than `nx.instance_variable_set(:@frame, nil)`, `instance_variable_set(:@strand, ...)`, or repeated `strand.update` calls bypassing the load path.
**Why:** Goes through the real loading path and keeps the spec resilient to internal changes. Specs that poke ivars silently rot when the load path evolves.
**How to spot:** `instance_variable_set(:@frame, ...)` or `instance_variable_set(:@strand, ...)` in specs; multiple `strand.update` calls in a row in a spec.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4476](https://github.com/ubicloud/ubicloud/pull/4476), [PR #4399](https://github.com/ubicloud/ubicloud/pull/4399), [PR #4438](https://github.com/ubicloud/ubicloud/pull/4438)

### R18. Insert-first when the resource usually doesn't exist; rescue conflict to recover — Concurrency
**Severity:** blocker
**Rule:** When creating a cloud resource that's unlikely to already exist, attempt the insert first and rescue an "already exists" error to fetch the existing one — rather than the get-fail-create-fail-get pattern.
**Why:** Get-first wastes API calls in the common path and complicates the rescue. Insert-first matches the actual lifecycle and avoids races.
**How to spot:** `existing = client.get(...) rescue nil; existing || client.create(...)` for resources we ourselves create.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #1622](https://github.com/ubicloud/ubicloud/pull/1622), [PR #2469](https://github.com/ubicloud/ubicloud/pull/2469), [PR #2782](https://github.com/ubicloud/ubicloud/pull/2782), [PR #3083](https://github.com/ubicloud/ubicloud/pull/3083)

## Major

### R19. DRY duplicated logic into a method, module, or shared helper — Naming and readability
**Severity:** major
**Rule:** When the same block of logic appears in multiple labels, progs, or specs (especially: GCP-op polling, error handling, sort/match patterns, semaphore reaping), extract it into a method or shared module.
**Why:** Recurring duplication accumulates drift; a shared method keeps cross-prog behavior consistent. This is the single most-cited theme in the corpus.
**How to spot:** Same `def` body in two progs; same 5-line sort/compare expression repeated; near-identical `rescue` shapes across labels; the same spec setup copy-pasted with minor adjustments.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4768](https://github.com/ubicloud/ubicloud/pull/4768), [PR #3013](https://github.com/ubicloud/ubicloud/pull/3013), [PR #3519](https://github.com/ubicloud/ubicloud/pull/3519)

### R20. Use `instance_double(Class, ...)` over `double(...)` — Testing patterns
**Severity:** major
**Rule:** Use `instance_double` (with the actual class) when you must mock; reserve plain `double` for cases where the class genuinely isn't known, with a comment explaining why. Better still, use the real object.
**Why:** Verifying doubles catch API drift; plain doubles silently accept stale interfaces and miss production breakage.
**How to spot:** `double("name")` or `double(method: ...)` in specs for objects whose class is known.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #5024](https://github.com/ubicloud/ubicloud/pull/5024), [PR #4504](https://github.com/ubicloud/ubicloud/pull/4504), [PR #5196](https://github.com/ubicloud/ubicloud/pull/5196)

### R21. Avoid `allow` for must-call assertions; don't pin `not_to receive` to specific args — Testing patterns
**Severity:** major
**Rule:** In specs that test a single behavior, prefer `expect(...).to receive(...)` over `allow`. Push `to receive(...)` to the lowest call site (with arguments). Push `not_to receive` to the highest-level method (omit arguments to avoid false negatives if argument shape changes). Use `.at_least(:once)` instead of `allow` when you want a count-flexible assertion.
**Why:** `allow` doesn't fail when the call goes missing; `not_to receive(:foo, args)` can silently pass if the args change.
**How to spot:** `allow(Clog).to receive(:emit)` in a single-behavior spec; `not_to receive(:something).with(specific_args)`; bare `allow` where the call is mandatory.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4876](https://github.com/ubicloud/ubicloud/pull/4876), [PR #3973](https://github.com/ubicloud/ubicloud/pull/3973), [PR #3889](https://github.com/ubicloud/ubicloud/pull/3889)

### R22. `Clog.emit` and similar logging stubs should `and_call_original` — Testing patterns
**Severity:** major
**Rule:** When asserting `Clog.emit` (or any logging/instrumentation method) was called, append `.and_call_original` so the actual log path is exercised.
**Why:** Bare expectations stub out the emit, so coverage/format issues in the real call path go untested.
**How to spot:** `expect(Clog).to receive(:emit).with(...)` without `.and_call_original`.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4702](https://github.com/ubicloud/ubicloud/pull/4702), [PR #4439](https://github.com/ubicloud/ubicloud/pull/4439), [PR #4348](https://github.com/ubicloud/ubicloud/pull/4348)

### R23. Use `typecast_params` for all request param access — API conventions
**Severity:** major
**Rule:** Access request parameters through `typecast_params` (with `nonempty_str`, `bool`, `int`, etc.) rather than `params["x"]`. For booleans, use `typecast_params.bool(...)` so missing parameters are `nil` (and the route can treat that as "unchanged").
**Why:** Centralizes coercion and validation, prevents type confusion, and integrates with the route's input contract. Direct `params[...]` access skips boundary checks.
**How to spot:** `params["foo"]` or `@params[:foo]` in routes; manual `to_i`/`to_s` on raw params; `params["bool"] == "true"` style checks.
**Examples:** [PR #3622](https://github.com/ubicloud/ubicloud/pull/3622), [PR #3979](https://github.com/ubicloud/ubicloud/pull/3979), [PR #4255](https://github.com/ubicloud/ubicloud/pull/4255), [PR #4505](https://github.com/ubicloud/ubicloud/pull/4505)

### R24. Don't break API backwards compatibility; missing params mean unchanged — API conventions
**Severity:** major
**Rule:** When updating a record from an API endpoint, treat a missing parameter as "no change", not as "set to default/false". Use `typecast_params.bool("flag")` (which returns `nil` when absent) and only mutate the field when the value is present and differs.
**Why:** Existing API clients send a subset of fields; defaulting missing booleans to `false` silently flips state and breaks deployed integrations.
**How to spot:** `record.update(field: typecast_params.bool("field"))` without a presence check; `params["field"] == "true"` defaulting to `false`; serializing every form field unconditionally.
**Examples:** [PR #3979](https://github.com/ubicloud/ubicloud/pull/3979), [PR #1119](https://github.com/ubicloud/ubicloud/pull/1119), [PR #2718](https://github.com/ubicloud/ubicloud/pull/2718), [PR #3928](https://github.com/ubicloud/ubicloud/pull/3928)

### R25. New web functionality must also be exposed via API/SDK/CLI — API conventions
**Severity:** major
**Rule:** Don't add web-only routes for user-visible features. The API, SDK, and CLI surface needs to reach parity, ideally in the same PR or an immediate follow-up. Call this out explicitly when you only see a `routes/web/` change.
**Why:** Web-only features create permanent feature gaps for programmatic users and users of the CLI/SDK.
**How to spot:** A new `routes/web/...` change without a corresponding `routes/api/...`, `cli-commands/`, `sdk/`, or `openapi/` update.
**Examples:** [PR #3979](https://github.com/ubicloud/ubicloud/pull/3979), [PR #2788](https://github.com/ubicloud/ubicloud/pull/2788), [PR #2915](https://github.com/ubicloud/ubicloud/pull/2915), [PR #4331](https://github.com/ubicloud/ubicloud/pull/4331), [PR #5234](https://github.com/ubicloud/ubicloud/pull/5234)

### R26. Use `eager` over `eager_graph` when not filtering/ordering on the joined table — Database
**Severity:** major
**Rule:** Use `eager [:assoc]` for plain preloads; reserve `eager_graph` for queries that filter or order by joined columns.
**Why:** `eager_graph` adds joins and complicates the query unnecessarily, and can multiply rows.
**How to spot:** `eager_graph [:assoc]` followed by no `where`/`order` referencing that association's columns.
**Examples:** [PR #4795](https://github.com/ubicloud/ubicloud/pull/4795), [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #3303](https://github.com/ubicloud/ubicloud/pull/3303), [PR #3953](https://github.com/ubicloud/ubicloud/pull/3953)

### R27. For non-Strand models, prefer plain `.create` over `.create_with_id` — Database
**Severity:** major
**Rule:** `Class.create_with_id` exists for `Strand` (R7) and for backwards compatibility on a few legacy models. New non-Strand model creation should use `.create(...)` directly. Don't introduce new `create_with_id` calls outside the Strand case.
**Why:** Reduces surface area; `create_with_id` for non-Strand models is a wart kept for compatibility, and Jeremy actively migrates calls back to `.create` when safe.
**How to spot:** `SomeNonStrandModel.create_with_id(...)` in new code; `create_with_id` paired with `generate_uuid` for non-Strand models.
**Examples:** [PR #2598](https://github.com/ubicloud/ubicloud/pull/2598), [PR #2645](https://github.com/ubicloud/ubicloud/pull/2645), [PR #2718](https://github.com/ubicloud/ubicloud/pull/2718), [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818)

### R28. Use `timestamptz`/`Time` (not `timestamp`) for timestamp columns — Database
**Severity:** major
**Rule:** Time-bearing columns must be `timestamptz` or use the Sequel `Time` type (which becomes `timestamptz` under our `pg_timestamptz` extension). Plain `timestamp` (without timezone) is wrong.
**Why:** Local-time columns produce drift across regions and DST and conflict with the rest of the schema.
**How to spot:** New `column :foo, :timestamp` (without `tz`); `column :foo, DateTime`.
**Examples:** [PR #2598](https://github.com/ubicloud/ubicloud/pull/2598), [PR #105](https://github.com/ubicloud/ubicloud/pull/105), [PR #1372](https://github.com/ubicloud/ubicloud/pull/1372), [PR #1797](https://github.com/ubicloud/ubicloud/pull/1797)

### R29. Don't introduce top-level constants outside their dedicated file — Naming and readability
**Severity:** major
**Rule:** Implementation-detail constants belong nested inside the class that owns them (e.g., `Page::Client`), not as top-level constants. Use class names (strings) instead of class references in lookup tables to avoid forcing autoload.
**Why:** Top-level constants don't reload cleanly in development; constant references in lookup hashes force autoloading and break reload semantics.
**How to spot:** New top-level `class`/`module`/constant added at the bottom of a file dedicated to a different class; lookup hashes keyed by `SomeClass` instead of `"SomeClass"`.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #4863](https://github.com/ubicloud/ubicloud/pull/4863), [PR #5286](https://github.com/ubicloud/ubicloud/pull/5286)

### R30. Avoid unnecessary allocations on hot paths — Performance
**Severity:** major
**Rule:** Use `Set.new(coll, &:attr)` / `coll.to_set(&:attr)` for membership tests over arrays; use `map!`/`sort!`/`sort_by!` when the receiver is already a fresh array; freeze constant literals (especially Ruby 3.4+ array literals) used inside `include?`. Avoid creating an intermediate `dup` when one local will do. Replace `find { |x| x.name == name }` over a constant array with a hash lookup.
**Why:** Hot paths repeat per request/strand; small allocations add up. `Set` membership is O(1) vs O(N), and a hash lookup beats `Array#find` for constant lookup tables.
**How to spot:** `xs.include?(y)` over a long array literal in a hot path; `xs.map { ... }.sort` where `xs` is freshly built; `["a", "b"]` literal in an `include?` call without `.freeze`; `array_constant.find { ... }` for repeated lookups.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #5262](https://github.com/ubicloud/ubicloud/pull/5262), [PR #4257](https://github.com/ubicloud/ubicloud/pull/4257), [PR #3462](https://github.com/ubicloud/ubicloud/pull/3462)

## Minor

### R31. Use the object directly instead of `nil?` (lonely-operator preference) — Naming and readability
**Severity:** minor
**Rule:** When you don't need to distinguish `nil` from `false`, write `if obj` rather than `unless obj.nil?` and `obj&.method` rather than building intermediate `nil?` branches.
**Why:** Shorter, clearer, and matches the Ruby idiom Jeremy applies in suggestions across many recent PRs.
**How to spot:** `unless x.nil?`, `if x.nil?` followed by `else` mutating, or `x.nil? ? a : b` where a falsy `x` could collapse the check.
**Examples:** [PR #3854](https://github.com/ubicloud/ubicloud/pull/3854), [PR #3819](https://github.com/ubicloud/ubicloud/pull/3819), [PR #4145](https://github.com/ubicloud/ubicloud/pull/4145), [PR #4270](https://github.com/ubicloud/ubicloud/pull/4270), [PR #4494](https://github.com/ubicloud/ubicloud/pull/4494)

### R32. Prefer `change { obj.reload.field }.from(X).to(Y)` and `expect(record.exists?)` for state checks — Testing patterns
**Severity:** minor
**Rule:** Use `change { obj.reload.field }.from(X).to(Y)` (over `by(N)`) for clarity, and `expect(record.exists?).to be false` (over reloading and checking nil) for destruction checks.
**Why:** `from`/`to` document expected pre- and post-state; `exists?` cleanly verifies a row is gone without raising.
**How to spot:** `change(Model, :count).by(1)`, `expect { record.reload }.to raise_error(...)`.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #5091](https://github.com/ubicloud/ubicloud/pull/5091), [PR #5200](https://github.com/ubicloud/ubicloud/pull/5200), [PR #4849](https://github.com/ubicloud/ubicloud/pull/4849), [PR #4188](https://github.com/ubicloud/ubicloud/pull/4188)

### R33. Use `Process.clock_gettime(Process::CLOCK_MONOTONIC)` for elapsed-time deltas — Correctness
**Severity:** minor
**Rule:** When measuring durations between two points in the same process, use the monotonic clock rather than `Time.now`.
**Why:** Wall-clock time can jump (NTP, DST, manual fix); the monotonic clock can't. It's also faster.
**How to spot:** `started = Time.now; ...; elapsed = Time.now - started` in new code.
**Examples:** [PR #4896](https://github.com/ubicloud/ubicloud/pull/4896), [PR #1828](https://github.com/ubicloud/ubicloud/pull/1828)

### R34. Migrations: omit `null: true` (it's the default) — Style
**Severity:** minor
**Rule:** In migration column definitions, `null: true` is the default — drop it to keep migrations terse. Spell out `null: false` only when you mean it.
**Why:** Reduces visual noise; matches the conventions Jeremy enforces in recent migration reviews.
**How to spot:** `add_column :foo, :bar, Integer, null: true` in new migrations.
**Examples:** [PR #3854](https://github.com/ubicloud/ubicloud/pull/3854), [PR #3865](https://github.com/ubicloud/ubicloud/pull/3865), [PR #1372](https://github.com/ubicloud/ubicloud/pull/1372)

### R35. Use `with_pk!` (or equivalent bang lookups) when a record must exist — Database
**Severity:** minor
**Rule:** When a lookup is supposed to always succeed, use `Model.with_pk!(id)` rather than `Model[id]`. The bang variant raises if the record is missing instead of returning `nil` and surfacing as a `NoMethodError` later.
**Why:** Documents intent and surfaces missing-record bugs at the lookup site.
**How to spot:** `Project[id]` or `Class.[](id)` followed by `.something` without a guard; the comment "this should never return nil".
**Examples:** [PR #3636](https://github.com/ubicloud/ubicloud/pull/3636), [PR #5050](https://github.com/ubicloud/ubicloud/pull/5050), [PR #2463](https://github.com/ubicloud/ubicloud/pull/2463)

### R36. Use `fail "BUG: ..."` (or `raise "BUG: ..."`) for invariant assertions — Error handling
**Severity:** minor
**Rule:** When the code reaches a state that should be unreachable, `fail "BUG: <message with offending values>"`. Make the message diagnostic — include enough context to debug from the trace alone.
**Why:** Distinguishes invariant violations from expected errors and improves on-call debuggability.
**How to spot:** `raise "unexpected"` without context; default `else` branches that silently `return nil` instead of asserting; `fail` with no message.
**Examples:** [PR #5091](https://github.com/ubicloud/ubicloud/pull/5091), [PR #1244](https://github.com/ubicloud/ubicloud/pull/1244), [PR #1661](https://github.com/ubicloud/ubicloud/pull/1661), [PR #1966](https://github.com/ubicloud/ubicloud/pull/1966)

### R37. Don't use `skip` in specs; use a conditional `unless ENV[...]` — Testing patterns
**Severity:** minor
**Rule:** Avoid `skip` in spec bodies. If a test only runs in some environments, wrap the `describe`/`it` in an `unless ENV["..."]` (or `if ENV["..."]`) so the example isn't created at all.
**Why:** `skip` produces noisy "pending" output for tests we never intend to run.
**How to spot:** `skip "..." unless ENV["FLAG"]` or `skip if condition` in new specs.
**Examples:** [PR #3884](https://github.com/ubicloud/ubicloud/pull/3884), [PR #3932](https://github.com/ubicloud/ubicloud/pull/3932), [PR #4141](https://github.com/ubicloud/ubicloud/pull/4141)

### R38. Don't mock `Time.now`; assert `be_within` — Testing patterns
**Severity:** minor
**Rule:** Don't stub `Time.now`/`DateTime.now` in specs — assert that the persisted timestamp is `be_within(N).of(Time.now)`, or that a field changed `from(nil)`.
**Why:** Time mocks couple specs to internals, often go unused once present, and obscure what behavior is being verified.
**How to spot:** `allow(Time).to receive(:now)` or `Timecop.freeze` in new specs.
**Examples:** [PR #4818](https://github.com/ubicloud/ubicloud/pull/4818), [PR #1583](https://github.com/ubicloud/ubicloud/pull/1583)

### R39. Commit hygiene: explain the why; split unrelated changes into separate commits — Process
**Severity:** minor
**Rule:** Commit messages should explain *why*, not just restate the diff. Split unrelated concerns (refactor + new feature, drive-by fix + main change) into separate commits so reviewers can review each in isolation. Don't bundle drive-by changes into a feature PR without a separate commit.
**Why:** PR-time review quality scales with commit organization; mixed commits force reviewers to mentally untangle each hunk.
**How to spot:** A single commit touching unrelated files; commit messages restating the diff (`"Update foo.rb"`); subsequent commits with `nit fixes` instead of being squashed.
**Examples:** [PR #1140](https://github.com/ubicloud/ubicloud/pull/1140), [PR #1138](https://github.com/ubicloud/ubicloud/pull/1138), [PR #4063](https://github.com/ubicloud/ubicloud/pull/4063), [PR #4079](https://github.com/ubicloud/ubicloud/pull/4079), [PR #4141](https://github.com/ubicloud/ubicloud/pull/4141)

## Non-actionable (excluded)

_Approximately 2,400 of the 11,263 ingested comments were classified as conversation/non-actionable and not turned into rules. These break down roughly into: thread replies starting with `@user` or `>` quoting (820 comments); short acknowledgements like "LGTM", "done", "thanks", "fixed", "good catch", "+1" (~530); author self-notes ("I'll fix this", "TODO", "will update", "let me check") (~400); and ultra-specific renames or one-off code suggestions with no transferable principle (the residual ~650). They were tracked but not promoted to rules; recurring patterns within them — e.g. requests for clearer commit messages — are absorbed into R39 rather than spread across multiple weak rules._
