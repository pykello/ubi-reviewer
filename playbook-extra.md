# Ubicloud Reviewer Playbook — Extras (Jeremy Evans patterns)

_Generated from 12,113 comments by jeremyevans across jeremyevans/sequel, jeremyevans/roda, jeremyevans/rodauth, and jeremyevans/forme. Last updated: 2026-05-13._

## How to use this playbook

These rules are derived from Jeremy Evans's reviews on his own OSS projects
(Sequel, Roda, Rodauth, Forme, …). They represent his coding standards as
applied outside ubicloud. `/ubi-review` walks them alongside the main
playbook; cite the rule number (E1, E2, …) when flagging an issue.

The dataset is dominated by ~10K of Jeremy's own commit messages, which
form a corpus of his self-narration style: how he frames the *why* of a
change, what he chooses to record, and how strict he is about testing,
backwards compatibility, and performance. Inline review comments and PR
review summaries on contributor PRs add the directly-applied review
patterns. Rules that translate to general Ruby/code quality are in the
main severity buckets below; rules that only make sense inside the
Sequel/Roda/Rodauth/Forme codebases are in the closing
"Framework-specific (informational)" section.

## Blocker

### E1. Never trust user input in identifier/symbol contexts — Security
**Severity:** blocker
**Rule:** Treat user-controlled strings as strings, not symbols/identifiers; never interpolate untrusted values into SQL, headers, or paths without escaping/whitelisting.
**Why:** Jeremy refuses to ship Roda's `symbolize_params` because symbol-from-untrusted-input mixes trusted and untrusted data and exposes downstream libraries (Sequel adapters, query builders) to injection. On the Sequel side he flagged multiple adapter methods (`tables`, `views`, `indexes`, `schema_parse_table`, `Connection#reorg`) as "vulnerable to SQL injection — use `literal` instead of trying to quote things yourself." He calls untrusted-symbol APIs a "huge foot-gun from a security perspective."
**How to spot:** `params[...].to_sym`, raw interpolation of params/env values into SQL strings, `eval(literal(v))`, or any place a user-supplied identifier is concatenated into a query/header/path without going through an escape helper.
**Examples:** [roda#117](https://github.com/jeremyevans/roda/pull/117), [sequel — symbolize_params discussion](https://github.com/jeremyevans/roda/pull/117#issuecomment-301277068), [sequel #639](https://github.com/jeremyevans/sequel/pull/639)

### E2. Add a regression test for every bug fix and every new code path — Testing
**Severity:** blocker
**Rule:** A bug fix or new feature is not done until a test exercises the exact path that previously failed; aim for 100% line *and* branch coverage on touched code.
**Why:** Jeremy repeatedly rejects PRs that lack tests ("we don't accept new plugins/features without tests", "before this can be merged you need to include tests for both of those scenarios in addition to fixing the code"). His own commit log is dotted with "Add specs for 100% branch coverage" and "Get to 100% branch coverage — as is typical, getting to 100% branch coverage uncovered multiple bugs." Coverage is not vanity; it surfaces real bugs.
**How to spot:** A diff that changes behavior in `lib/` without a corresponding change in `spec/` or `test/`; a new conditional with no spec for the false branch; a fix described only in the commit body with no failing-then-passing assertion.
**Examples:** [sequel#2093](https://github.com/jeremyevans/sequel/pull/2093), [rodauth#264](https://github.com/jeremyevans/rodauth/pull/264), [rodauth#502](https://github.com/jeremyevans/rodauth/pull/502)

### E3. Tests must assert state, not just message text — Testing
**Severity:** blocker
**Rule:** When testing error/edge cases, assert that the resulting *object state* (e.g. instance variables, returned model, persisted row) is correct, not just that the error message matches a string.
**Why:** In sequel#2079 Jeremy caught a bug where the test passed because it only checked the exception message — meanwhile the implementation was setting the instance variable on the class instead of the instance. "You don't catch this because you only test for the message and not for the model value. The tests should be updated to test that the model is set correctly." Same pattern in rodauth tests: "the spec doesn't appear to check that you can decode the JWT — you should have it make a request after login that can determine whether the session is logged in."
**How to spot:** `assert_raises ... { ... }` or `expect(...).to raise_error(SomeError, "msg")` with no follow-up assertion on the involved object's state; tests that only check `error.message`.
**Examples:** [sequel#2079](https://github.com/jeremyevans/sequel/pull/2079#discussion_r1327973012)

### E4. Don't break backwards compatibility silently — Correctness
**Severity:** blocker
**Rule:** Backwards-incompatible behaviour changes need an explicit opt-in (option, plugin, major version), a deprecation warning, and a CHANGELOG entry; never change a default in a way that breaks existing callers without one.
**Why:** This is the single most-repeated theme in Jeremy's reviews. Examples: "This is not backwards compatible, and will break code that uses `raise MassAssignmentRestriction`" (sequel#2079), "This breaks backwards compatibility, because these methods are exposed as auth methods and are overridable" (rodauth), "I'm OK with supporting this, but it must be conditional and off by default for backwards compatibility" (sequel#2108), "this change wasn't announced in the release notes or accompanied by a deprecation warning … is not reason enough to just drop backwards compatibility" (sequel). When breakage is unavoidable he insists on a deprecation cycle ("RODAUTH3" markers, `Sequel::Deprecation`, etc.).
**How to spot:** Renamed/removed public methods, changed default values for options, changed return types, raising where the previous code returned, narrowing accepted argument types, behaviour that diverges between callers that previously got the same result.
**Examples:** [sequel#2079](https://github.com/jeremyevans/sequel/pull/2079#discussion_r1327401818), [rodauth#165](https://github.com/jeremyevans/rodauth/pull/165#discussion_r628574962), [sequel#2108](https://github.com/jeremyevans/sequel/pull/2108)

### E5. Mutable shared state must be thread-safe or frozen — Concurrency
**Severity:** blocker
**Rule:** If a structure can be read from multiple threads (cache, options hash, association reflection, dataset opts), either freeze it or guard every read/write with the appropriate mutex/synchronize; never mutate state that other threads are reading.
**Why:** Jeremy on sequel: "if I'm reading this correctly, this is not thread safe. It appears that it relies on the mutation of `dataset.opts[:returning]` which can be shared across threads … you should probably make sure that `dataset.opts[:returning]` is frozen (as well as each array inside of it)." On roda: he added `RodaCache` specifically so per-class caches can be either thread-safe (mutex) or frozen (after `Roda.freeze`). On the Sequel `core_extensions?` `-w` patch: he rejected it because "it isn't thread safe … there is a race condition that causes it to be undefined for a small period of time." He also recommends freezing `Sequel::Database` instances in production and tests "to reduce the risk of thread safety issues."
**How to spot:** Class- or module-level mutable hashes/arrays that are written after initialization; lazy initialization without a mutex (`@x ||= …` of a non-trivial structure shared across threads); mutation of an `opts`/`@options` hash that's been handed out to callers.
**Examples:** [sequel — thread safety discussion (PR #1184)](https://github.com/jeremyevans/sequel/issues/1184), [roda — RodaCache commits](https://github.com/jeremyevans/roda/commits/master), [sequel — Database#freeze commit](https://github.com/jeremyevans/sequel/commits/master)

### E6. Don't `rescue Exception` or blind-rescue — Error handling
**Severity:** blocker
**Rule:** Rescue the *specific* exception class(es) the underlying call can raise. Never `rescue Exception`, never use a bare `rescue` that swallows everything, never wrap unrelated operations in one rescue.
**Why:** Jeremy on a Sequel adapter PR: "`Database#execute` probably should not rescue `Exception`. You should only rescue the specific exception class(es) raised by the underlying adapter. `Database#table_exists` appears to be able to go into an infinite loop if the database still raises an exception. Again, you should only be rescuing the specific exception class, as currently you'll retry if an unrelated exception such as an interrupt is raised." On a Roda PR: "the current implementation with the blind rescue is a bit scary."
**How to spot:** `rescue Exception`, bare `rescue` without a class, retry loops around `rescue StandardError`, rescues spanning multiple unrelated calls.
**Examples:** [sequel — adapter exception discussion](https://github.com/jeremyevans/sequel/pull/639), [roda — raw_payload discussion](https://github.com/jeremyevans/roda/issues)

### E7. Raise structured errors, not strings — Error handling
**Severity:** blocker
**Rule:** Raise an exception class (ideally a project-specific one such as `Sequel::DatabaseError`, `Roda::RodaError`, `Rodauth::ConfigurationError`), never `raise "some message"`.
**Why:** Jeremy: "Don't raise strings as errors (`Connection#prepare`, `Connection#execute_prepared_statement`, `Database#_execute`). You should probably raise them as `Sequel::DatabaseError`s." On rodauth#458: "Can we rename the custom error class from `Error` to `ConfigurationError` to make clear this is an error in the user's configuration?" — class names communicate intent.
**How to spot:** `raise "literal string"`, `raise SomeError` (no message), exceptions reused across unrelated failure modes.
**Examples:** [sequel — raise strings discussion](https://github.com/jeremyevans/sequel/pull/639), [rodauth#458](https://github.com/jeremyevans/rodauth/pull/458#pullrequestreview-2489167120)

### E8. Don't introduce silent retries or fallbacks that mask errors — Correctness
**Severity:** blocker
**Rule:** If the database/external service raises, propagate the error. Do not retry on integrity-constraint or other "real" failures; do not auto-fallback to a different code path that hides the original problem.
**Why:** Jeremy: "While automatically retrying operations can make some things easier, it can hide bugs, and Sequel's philosophy is if the database raises an error, the error should be raised." On a Sequel duplicate-column PR: "I'm not sure I like this approach of silently hiding the problem … this should probably raise an error by default."
**How to spot:** `rescue ... retry` loops; conditionals that swallow an exception and continue with partial data; fallback branches that quietly return `nil`/`false` instead of bubbling the error.
**Examples:** [sequel — retry on integrity violation discussion](https://github.com/jeremyevans/sequel/issues)

### E9. Don't reintroduce trailing whitespace or unrelated whitespace churn — Commit hygiene
**Severity:** major (promoted from minor only when it is the *whole* PR)
**Rule:** Keep refactors to behaviour changes; do not mix whitespace-only edits, formatting passes, or unrelated file reformatting into a feature/fix PR.
**Why:** Jeremy on rodauth#369: "It would be best to avoid unnecessary whitespace changes when refactoring." On rodauth#502: "could you please remove the unrelated whitespace changes, and add a spec?" The reason is review surface area and revert-ability — a one-line bug fix buried under 100 whitespace lines is hard to back out.
**How to spot:** Diffs with many `-`/`+` lines that differ only in indentation, blank lines, or quoting; rename/rewrap of unrelated comments; reordering of unrelated methods.
**Examples:** [rodauth#369](https://github.com/jeremyevans/rodauth/pull/369#discussion_r1349383631), [rodauth#502](https://github.com/jeremyevans/rodauth/pull/502#pullrequestreview-4136167380)

## Major

### E10. Commit messages explain *why*, not just *what* — Commit hygiene
**Severity:** major
**Rule:** Every non-trivial commit's body explains the motivation, the alternatives considered, and any behaviour/back-compat implications. Subject line is a short imperative summary; body wraps at ~72 chars.
**Why:** Pattern across thousands of Jeremy's own commits. Examples: "Use div with nested p tags instead of spans for readonly textarea inputs — For text inputs, since they are single lines, using a span is fine. However, since textareas are designed to be used for multiline input, using a span results in visual issues because it doesn't preserve the line breaks. Using a div with nested p tags for each paragraph and br tags for each individual line break is probably the closest way to get a similar visual style in readonly formatting." Refactor commits explicitly call out *why* the refactor and what it enables. Workaround commits name the upstream bug and Ruby/dependency version.
**How to spot:** Commits with only a subject line for non-trivial diffs; subjects like "fix bug", "update code", "refactor" with no body; subjects that paraphrase the diff rather than the reason.
**Examples:** [forme — Refactor namespace/:key option handling](https://github.com/jeremyevans/forme/commits/master), [sequel — Support Database#freeze](https://github.com/jeremyevans/sequel/commits/master)

### E11. Split unrelated changes into separate commits — Commit hygiene
**Severity:** major
**Rule:** One logical change per commit. If you also notice an adjacent typo, unrelated refactor, or CHANGELOG edit, commit it separately.
**Why:** rodauth#369: "I think the change makes sense. However, it's probably better as a separate commit." sequel#2343: "please separate the commits appropriately (one just for `:only`, the other just for `:include_indexes`), with appropriate commit messages." His own commit history shows tiny, single-purpose commits (e.g. "Update CHANGELOG" landed separately from "Support :raise option for typecast_params convert_each!").
**How to spot:** A single commit that touches multiple unrelated subsystems; a commit subject containing "and" linking two changes; mixed refactor + behaviour change + doc update.
**Examples:** [sequel#2343](https://github.com/jeremyevans/sequel/pull/2343#pullrequestreview-3434503927), [rodauth#369](https://github.com/jeremyevans/rodauth/pull/369#discussion_r1349638639)

### E12. Don't move code around when refactoring unless necessary — Refactor hygiene
**Severity:** major
**Rule:** When refactoring, preserve existing structure (transaction boundaries, indentation, method order) unless the change requires moving them. Don't relocate a line just because you're touching the file.
**Why:** rodauth#369: "This moves the code from inside the transaction block to outside. Not a big deal in this case, but we should probably attempt to avoid unnecessary changes when refactoring." This makes the actual change visible in the diff and makes reverts trivial.
**How to spot:** Refactor diffs where the meaningful logic change is buried inside a sea of moved-but-unchanged lines; methods that are moved up/down a file without reason; code that crosses a transaction/lock boundary unnecessarily.
**Examples:** [rodauth#369](https://github.com/jeremyevans/rodauth/pull/369#discussion_r1349382252)

### E13. Add an optional argument at the end of an existing signature — API design
**Severity:** major
**Rule:** When adding a new optional parameter to an existing method, append it at the end of the argument list (or use a keyword arg / options hash). Never insert it before an existing positional argument.
**Why:** sequel#1962: "When adding an optional argument to an existing method, the optional argument should always be added at the end." Inserting in the middle silently breaks every caller that uses positional arguments.
**How to spot:** A method signature whose argument list is reordered; a new param sitting between two existing positional params.
**Examples:** [sequel#1962](https://github.com/jeremyevans/sequel/pull/1962#discussion_r1020937189)

### E14. Don't add optional positional args to "configuration" methods — API design
**Severity:** major
**Rule:** Methods whose primary purpose is configuration (DSL methods, setters) should not take optional positional arguments. Use keyword args or a separate method.
**Why:** Jeremy in rodauth: "In general I don't want to have configuration methods take optional arguments. `remove_remember_key` and `csrf_tag` are the only configuration methods that currently do, and if not for backwards compatibility, I would probably change both. Additionally, adding optional parameters to configuration methods that don't currently take parameters is bad for backwards compatibility, because then code that starts an already defined configuration method with the optional argument would break."
**How to spot:** A DSL-style method gaining a second/third positional argument; setters that overload behaviour based on arity.
**Examples:** [rodauth — configuration methods discussion](https://github.com/jeremyevans/rodauth/pulls)

### E15. Name methods for their semantics, not their mechanics — Naming
**Severity:** major
**Rule:** Method names describe what the caller wants (`login_response`, `account_status`, `add_transaction_hook`, `transaction_hooks`), not the mechanical implementation (`do_login_thing`, `data`, helper-style helper names). Don't reuse a confusing prefix from an unrelated abstraction.
**Why:** sequel#1198: "We should probably rename this `add_transaction_hook`", "This should probably be renamed to `transaction_hooks`", "I think it would be better to change this method so that it returned the hash to use (possible name: `transaction_state_hash`)." rodauth#369: "`login_response` makes sense as an auth method, but not as an auth value method." rodauth#452: "I would like a better method name. The issue I have with `pending?` is that Rodauth is designed to handle cases where certain actions do not require 2FA, and other cases do. Just because 2FA is available does not mean that it is required by the application."
**How to spot:** Methods whose name describes the algorithm (`recompute_x`, `mutate_y`) rather than the contract; predicates whose name doesn't match the cases they return true/false for; new methods echoing an unrelated existing convention.
**Examples:** [sequel#1198](https://github.com/jeremyevans/sequel/pull/1198#discussion_r64956954), [rodauth#452](https://github.com/jeremyevans/rodauth/pull/452#pullrequestreview-2441109306)

### E16. Don't extract a method just for the sake of extraction — Refactor hygiene
**Severity:** major
**Rule:** Only extract a private helper when (a) it has more than one caller, or (b) you specifically want it overridable from a subclass/plugin. Extraction with neither is busywork that obscures control flow.
**Why:** rodauth#321: "I'm not generally in favor of moving code called a single place into a method, unless there is a desire to override the behavior. Especially in `forget_login` where all code is being moved into another method. Do you plan on overriding these new methods? If not, I would be OK with the `set_remember_cookie` extraction, but I don't see the point of moving all `forget_login` code into another method and having `forget_login` call that."
**How to spot:** A new private method called from exactly one site; an extraction PR that doesn't add any new caller or subclass.
**Examples:** [rodauth#321](https://github.com/jeremyevans/rodauth/pull/321#pullrequestreview-1347063676)

### E17. Prefer overriding methods over adding configuration options — API design
**Severity:** major
**Rule:** Before adding a new option/setting, ask whether overriding a method on a subclass/plugin already covers the use case. Add an option only when the variability is common enough to deserve a documented seam.
**Why:** roda#306: "I don't think storing options for this is good. If users want to override the CSS/JS, they can override the related class methods (or load a plugin that overrides them) … I don't think the need to modify the exception page css/js is common enough to warrant plugin options. As long as we add methods, applications wanting to modify the css/js can override them and call super." The bar for adding an option is high; the bar for exposing an overridable method is lower.
**How to spot:** A new option whose only effect is to replace a small block of code; a configuration knob with one expected value; "make X configurable" PRs that don't explain who needs each setting.
**Examples:** [roda#306](https://github.com/jeremyevans/roda/pull/306#discussion_r1093508674)

### E18. Don't silently overwrite or skip user-provided values — Correctness
**Severity:** major
**Rule:** If a caller supplies a value (an option, an attribute, an `id`), respect it. Don't silently overwrite it from defaults, don't ignore unsupported combinations — error or document.
**Why:** Jeremy's commit "Get to 100% branch coverage" surfaced "the bs3 error handler didn't handle them" and "boolean inputs in the Sequel forme plugin didn't correctly handle explicit nil/false `:value` options in all cases." Edge values (`nil`, `false`, empty arrays) are a recurring source of bugs because code paths default before checking.
**How to spot:** `value ||=` on something the caller may legitimately set to `nil`/`false`; `merge` that overwrites caller values instead of being overwritten by them; default branches that fire when an option *was* provided but was falsy.
**Examples:** [forme — 100% branch coverage commit](https://github.com/jeremyevans/forme/commits/master)

### E19. Match each `super` call to the class hierarchy — Correctness
**Severity:** major
**Rule:** When overriding a method, call `super` (with the right args) unless you're deliberately replacing behaviour. Document overrides that intentionally skip `super`.
**Why:** roda#398: Jeremy's suggested edit added the parenthetical "(making sure to call +super+)" — calling super is the documented contract. The rodauth `reset_password` discussion shows the same idea: "extend it in the `reset_password_verifies_accounts` feature to do `[super, account_unverified_status_value].flatten`" — the super chain composes feature behaviour.
**How to spot:** Method overrides in subclasses/plugins/features that never call `super`; overrides that call `super` without forwarding all arguments; new modules included with `prepend` without thinking about whether `super` will be invoked.
**Examples:** [roda#398](https://github.com/jeremyevans/roda/pull/398#discussion_r2337535182), [rodauth#499](https://github.com/jeremyevans/rodauth/pull/499#discussion_r2739373985)

### E20. Make caches and hot paths allocation-light — Performance
**Severity:** major
**Rule:** In code that runs every request / every row, avoid creating new strings, hashes, arrays, procs, or regexps you could reuse. Cache regexps in constants; freeze string literals; avoid splatting; use `match` and capture, not `=~` and `$~`.
**Why:** Jeremy's commits repeatedly track allocation: "Reduce allocations for date/datetime :as=>:select", "Improve string matching by 10-20% — This changes `_match_string` to only perform a single allocation", "Add optimized `is_get?` method — the default `get?` method allocates a couple of strings, save those allocations by using frozen string constants", "Optimize render_each and each_part default local selection — uses an allocationless and regexp-free approach … about 3x faster", "Avoid string allocation in `hash_routes` plugin", "Reduce hash allocations when using the chunked and render plugins." On roda#5: "There is currently a new regexp created every time. It's probably better to cache this regexp, similar to how the multi_route plugin caches the regexp it uses."
**How to spot:** Regexp/`Hash.new`/`Array.new` literals inside a hot method; `"foo".freeze` instead of using `frozen_string_literal: true`; `arr.map { ... }.to_a`; `string =~ regexp; $~[1..-1]`; `Proc.new` from a block.
**Examples:** [roda#5](https://github.com/jeremyevans/roda/pull/5#discussion_r18006395), [roda — is_get? optimization commit](https://github.com/jeremyevans/roda/commits/master)

### E21. Don't add complexity for `-w` / uninitialized-ivar warnings — Style/Performance tradeoff
**Severity:** major
**Rule:** Initializing instance variables to `nil` and adding `defined?` checks purely to silence `-w` warnings is not worth it. If a warning matters, fix it properly; if it doesn't, filter it (the `warning` gem) — don't bloat hot code.
**Why:** Jeremy: "Sequel by design does not initialize instance variables, as doing so reduces performance … Setting the instance variables to nil (`@foo ||= nil`) has a significant memory penalty. Checking for instance variable before every use has a significant performance penalty (3-7 times slower)." He also rejected `-w` patches because "if I apply this `-w` patch, someone else will request another `-w` patch that fixes the warnings in their app, and that's not a road I want to travel."
**How to spot:** `@foo ||= nil` lines at the top of a method/class; widespread `defined?(@foo)` guards; PRs whose only motivation is "fixes -w warnings".
**Examples:** [sequel — uninitialized ivar policy](https://github.com/jeremyevans/sequel/issues/1184)

### E22. Use `frozen_string_literal: true` and add tests under `--enable-frozen-string-literal` — Style/Performance
**Severity:** major
**Rule:** New Ruby files start with `# frozen_string_literal: true`. Don't rely on string mutation. If you need a mutable buffer, allocate one explicitly (`String.new` / `+""`).
**Why:** Jeremy converted all four projects ("Add frozen_string_literal: true to files", "Add support for running with --enable-frozen-string-literal on ruby 2.3") and routinely fixes frozen-string regressions ("Fix frozen string literal issue in explicit labeler", "Make multibyte_string_matcher_spec work correctly with --enable-frozen-string-literal"). Frozen literals are both correctness (catches accidental mutation) and performance (literal sharing).
**How to spot:** New `.rb` files without the magic comment; `string << "..."` on a literal; `gsub!`/`upcase!`/etc. on a string that may be frozen.
**Examples:** [forme — frozen_string_literal commit](https://github.com/jeremyevans/forme/commits/master), [roda — frozen_string_literal commit](https://github.com/jeremyevans/roda/commits/master)

### E23. Don't ship dead code, commented-out code, or "just in case" branches — Code hygiene
**Severity:** major
**Rule:** If code is unreachable or unused, delete it. If it's conditional on something we no longer support, delete the condition. Don't comment-out — delete and rely on git history.
**Why:** rodauth#117: "It seems odd to just comment this out. Shouldn't it be conditional (run for Bigint, not run for uuid)?" sequel#2093: "This code should be removed." Jeremy regularly deletes deprecated and removed support in dedicated commits.
**How to spot:** `# old_thing` blocks of commented code; `if false; ... end` guards; conditionals on Ruby/library versions older than the declared minimum; methods only called from tests.
**Examples:** [rodauth#117](https://github.com/jeremyevans/rodauth/pull/117#discussion_r471120004), [sequel#2093](https://github.com/jeremyevans/sequel/pull/2093#discussion_r1388506258)

### E24. Tests run on real conditions, not on mocked-out values — Testing
**Severity:** major
**Rule:** When a fix targets a specific scenario (custom SQL, specific RDBMS, specific Ruby version), the test must exercise that scenario, not a generic mock.
**Why:** sequel#1990: "The issue you are trying to fix is only present for datasets using custom SQL (no SQL server will return a NULL value for `SELECT 1`). So the spec should also be modified to use custom SQL." sequel#2249: "one of the prerequisites would be that specs are added to test for expected behavior." sequel#2093: "you need to check whether the migration has already been applied … please include tests for both of those scenarios in addition to fixing the code."
**How to spot:** Spec hits the new code only through a happy-path scaffold; spec uses mocks where the bug requires real DB output; spec only asserts on the input side, not the output of the corrected path.
**Examples:** [sequel#1990](https://github.com/jeremyevans/sequel/pull/1990#discussion_r1095248809), [sequel#2249](https://github.com/jeremyevans/sequel/pull/2249#pullrequestreview-2425609731)

### E25. Don't pin upper bounds in gem dependencies — Dependencies
**Severity:** major
**Rule:** Use `>=` constraints; avoid `<` or `~>` upper bounds unless you have *actually verified* the upper version breaks something. Library gems should not pre-emptively pin.
**Why:** forme#16: "I'm very much against `<` or `~` in library gem specs unless you know that newer versions of the dependencies are not compatible. I'm OK with adding `>=` to the gem specs, you just need to show that that version works and that the version before that does not." Pessimistic version locking causes downstream resolution pain without protecting anyone.
**How to spot:** New `gemspec`/`Gemfile` lines with `< X` or `~> X` for runtime deps; PRs that pin to a working version after a transient CI flake.
**Examples:** [forme#16](https://github.com/jeremyevans/forme/pull/16#issuecomment-243533877)

### E26. Don't load adapter/optional libraries at top level if they're not always used — Dependencies
**Severity:** major
**Rule:** Require optional dependencies inside the method/plugin that needs them, not at file load time. Don't make every user pay for a feature only some use.
**Why:** Jeremy moved the bs3 code into `forme/bs3` "so that people who don't use this don't pay the penalty for loading it." Roda comment: "Roda works with any template library supported by tilt, it does not assume that the user will be using erb templates … if the user chooses to use a different one, they shouldn't take the memory hit for requiring libraries that they will not be using." On roda#5: `open-uri` "modifies the behavior of the core `open` method, and I'd really like to avoid that if possible."
**How to spot:** `require 'some_optional_lib'` at the top of a core file; bringing in a heavyweight dep for a single small feature; requires that monkey-patch core classes (`open-uri`).
**Examples:** [forme#14](https://github.com/jeremyevans/forme/pull/14#issuecomment-141755555), [roda#5](https://github.com/jeremyevans/roda/pull/5#discussion_r18006665)

### E27. Update CHANGELOG/docs/migrations as part of the same PR — Documentation
**Severity:** major
**Rule:** A behaviour change ships with its CHANGELOG entry, doc update (rdoc/README), and any required migration in the same PR. New public methods are documented; `rake check_method_doc`-style tooling enforces it.
**Why:** rodauth#369: "all auth methods added must be documented (run `rake check_method_doc` to check documentation)." sequel#2343: "update the documentation … to mention `include_invalid`." Jeremy's own commits include "Update CHANGELOG, README, and spec for last commit" as a recurring follow-up pattern. He's also strict about *where* docs go: "the change should be made in the main repository in the www folder, not directly to the gh_pages branch."
**How to spot:** Public method/option added without rdoc; CHANGELOG unchanged for a user-visible change; doc updates in a separate "doc-only" PR landing later.
**Examples:** [rodauth#369](https://github.com/jeremyevans/rodauth/pull/369#pullrequestreview-1662894244), [sequel#2343](https://github.com/jeremyevans/sequel/pull/2343#pullrequestreview-3434503927)

### E28. Don't ship feature flags/options that change defaults in a backwards-incompatible way without an opt-in — API design
**Severity:** major
**Rule:** If a new behaviour is potentially breaking, ship it behind an option/configuration method that defaults to the current behaviour. Document a future major where the default will flip.
**Why:** rodauth — JWT status code change: "Technically, this is a breakage of backwards compatibility, since users currently expecting a 400 status for expired tokens may break. So we probably can't change the default behavior until a major version bump." sequel#2108: "I'm OK with supporting this, but it must be conditional and off by default for backwards compatibility." This is the gentle path corollary to E4.
**How to spot:** New behaviour that always activates after merge; default values changed in a single PR.
**Examples:** [sequel#2108](https://github.com/jeremyevans/sequel/pull/2108#pullrequestreview-1795409672)

### E29. Be cautious with generic / "permissive" parsing — Security & UX
**Severity:** major
**Rule:** Don't trust user-supplied paths, redirect targets, or authentication tokens without validation. Reject odd inputs early. For auth state, prefer not extending tokens that aren't actively used.
**Why:** rodauth — path validation: "Blindly trusting any path provided by the user seems to be a bad idea to me. Without some sort of path validation, I think there may be a risk of some form of header injection." rodauth — remember token: "The issue with automatically extending memory tokens when not in use is the same issue with automatically extending any token not in use, in that an attacker who gets access to an old token may be able to use it because the old token was continually extended."
**How to spot:** Redirects that take the next-url from a parameter without an allowlist; auth flows that silently refresh long-lived tokens; parsers that accept unbounded sizes (see E30).
**Examples:** [rodauth — path validation discussion](https://github.com/jeremyevans/rodauth/pulls), [rodauth — remember token discussion](https://github.com/jeremyevans/rodauth/pulls)

### E30. Bound the size of untrusted input — Security
**Severity:** major
**Rule:** Cap the size of user-supplied parameters before processing. Reject or truncate values larger than the bound.
**Why:** Rodauth commit "Limit parameter bytesize to 1024 by default, override with `max_param_bytesize` configuration method — None of the parameters that Rodauth deals with should be over this size. All parameters are user submitted and potentially hostile, so I think it makes sense to enforce a limit." Generalisable to anywhere ubicloud accepts user input that flows into expensive parsing/storage.
**How to spot:** `params[...]` consumed without a size check; uploads/streams without an upper bound; JSON bodies parsed without `JSON.parse(..., max_nesting:)`-style limits.
**Examples:** [rodauth — max_param_bytesize commit](https://github.com/jeremyevans/rodauth/commits/master)

### E31. Use the platform's idioms, not your framework's — Correctness
**Severity:** major
**Rule:** Cookies, sessions, redirects, headers — use the standard interface (Rack spec, HTTP RFCs) rather than custom indirection. Defer to the platform when it already has a correct answer.
**Why:** roda#167: "Roda's common_logger plugin is based on Rack::CommonLogger, and supports the same type of logger … I don't see a good reason to change this. It may be better for `Async.logger` (or other 'modern logger') to adopt the standard Logger interface." rodauth `httponly` default: "While this isn't necessarily a vulnerability in Rodauth itself, as it is security related, I'll put out a new release with it later today." (Defaults should match the conservative HTTP-cookie norm.)
**How to spot:** Custom logger/cookie/header abstractions; reinventing CSRF/cookie/session/redirect handling instead of delegating to the framework's primitives.
**Examples:** [roda#167](https://github.com/jeremyevans/roda/pull/167#issuecomment-514050766)

### E32. Provide a benchmark for performance claims — Performance
**Severity:** major
**Rule:** "Faster"/"more efficient" PRs include a reproducible benchmark and numbers. No numbers, no merge.
**Why:** roda#174: "Do you have any benchmarks for what performance differences are with this approach? If not, can you put together a benchmark to see what effect this has on performance?" roda JSON discussion: "Can you update the benchmark to actually generate some JSON inside the proc and the method (say `{'a'=>1, 'b'=>[1,2,3]}.to_json`)?" Sequel discussions similarly demand benchmarks before accepting "this should be faster" claims.
**How to spot:** PR description claims a speedup with no `benchmark/ips` or measured numbers; performance change that comes at a complexity cost without a measured payoff; "looks faster" comments in commit bodies.
**Examples:** [roda#174](https://github.com/jeremyevans/roda/pull/174#issuecomment-544276364)

### E33. Don't add defensive type-checking Ruby already does — Style
**Severity:** major
**Rule:** Don't write `raise TypeError unless x.is_a?(Hash)` if `x.merge!(...)` will already give a clear error. Trust Ruby's built-in type errors unless you can provide actively better diagnostics.
**Why:** Jeremy on Sequel: "Sequel doesn't do this type of defensive type checking in most cases. `Hash#merge!` should give you an exception if the type is not valid. If you really want a more descriptive error message when a non-Hash is passed to `Hash#merge!`, you should probably provide a patch to ruby itself."
**How to spot:** `raise ArgumentError unless x.is_a?(...)` immediately followed by a built-in method call that would itself raise; `x.respond_to?(:foo)` checks followed by `x.foo`.
**Examples:** [sequel — defensive type checking discussion](https://github.com/jeremyevans/sequel/issues)

### E34. Document the "why" of guard clauses near the guard, not in a far-off rationale — Documentation
**Severity:** major
**Rule:** When a method has a non-obvious early-return or special case, leave an explanatory comment at the call site. Jeremy's own commit bodies are this comment.
**Why:** Many of Jeremy's commits read as "Add explicit comment for X". Sequel: "Move and correctly guard spec — Roda still supports Ruby 1.9, so you cannot use keyword arguments directly in the specs." Roda: "Don't freeze the rack app inside freeze — The rack app can be a middleware instance, and not all middleware was designed to handle freezing." These rationales should travel with the code in some form (commit body + adjacent comment).
**How to spot:** Cryptic early returns; version conditionals (`if RUBY_VERSION >= '...'`) without explanation; `nocov` markers without a one-line reason.
**Examples:** [roda — Don't freeze rack app commit](https://github.com/jeremyevans/roda/commits/master)

### E35. Avoid `eval` and other code-execution primitives on dynamic strings — Security
**Severity:** major (promoted to blocker when the input could come from untrusted callers)
**Rule:** Don't `eval`, `instance_eval`, `class_eval` strings built from runtime values. Use `define_method`/`send` with explicit symbols when you need dynamic dispatch.
**Why:** Jeremy on the Sequel adapter audit: "`Database#execute_prepared_statement` should probably rescue the specific errors that can be raised and use `raise_error`. It also should not use `eval`, as that could probably be used for code injection. args should generally be ruby objects anyway, so I don't see the need for `eval(literal(v))`."
**How to spot:** `eval(...)` with anything other than a constant string; `class_eval(string)` where `class_eval(&block)` would do; `instance_eval` of caller-provided strings.
**Examples:** [sequel — eval audit discussion](https://github.com/jeremyevans/sequel/pull/639)

### E36. Be specific about which database/platform a feature applies to — Correctness
**Severity:** major
**Rule:** Database-specific (or OS-specific, or Ruby-version-specific) features must (a) declare the scope in their documentation, and (b) be guarded so they don't run on other platforms.
**Why:** sequel#2249: "This should be clear that it is MySQL/PostgreSQL only." sequel#2343: "`ONLY` is only supported on PostgreSQL 11+, so add the appropriate spec guard." Applies equally in ubicloud-land to cloud-provider or kernel-version-specific code paths.
**How to spot:** Feature added without "(PostgreSQL 11+)" / "(Linux only)" / similar doc note; spec missing the version/platform guard; default-on for an option that only works in one environment.
**Examples:** [sequel#2249](https://github.com/jeremyevans/sequel/pull/2249#discussion_r1835552469), [sequel#2343](https://github.com/jeremyevans/sequel/pull/2343#pullrequestreview-3434503927)

### E37. Don't change error status codes for "consistency" — Compatibility
**Severity:** major
**Rule:** HTTP status codes are part of the public API. Don't change a 200→4xx or 400→401 without a compat option, even if the new code is "more correct."
**Why:** rodauth: "Using 200 as a status for errors was not intentional, that was just the default … For backwards compatibility, the 400 behavior for JSON API responses is kept, but it can switch to the newer 4xx statuses via the `json_response_custom_error_status?` configuration method. Rodauth 2 will default …" Behaviour can change at major versions; mid-stream it must be opt-in.
**How to spot:** Diffs that change `status 200`/`status 400` literals; new conditionals that route success-vs-error to a different code; CHANGELOG entries that say "now returns 4xx" without "opt in via".
**Examples:** [rodauth — 4xx status commit](https://github.com/jeremyevans/rodauth/commits/master)

### E38. Don't introduce migrations that lose security or strictness — Database
**Severity:** major
**Rule:** Database migrations preserve `NOT NULL`, indexes, foreign keys, and unique constraints. Reducing strictness is a behaviour change requiring justification. Adding new tables/columns should set them up correctly the first time.
**Why:** Rodauth: "Mark account_id field as NOT NULL and add an index on it. Users that already have created this table should update it: `alter_table(:account_jwt_refresh_keys) do; set_column_not_null :account_id; add_index :account_id, :name=>:account_jwt_rk_account_id_idx; end`." Jeremy ships migrations along with the model change and is explicit about expected schema state.
**How to spot:** New columns without `null: false` where appropriate; missing FK indexes; missing unique constraints on columns the application treats as unique; column-removal migrations without a sibling code change.
**Examples:** [rodauth — account_jwt_refresh_keys commit](https://github.com/jeremyevans/rodauth/commits/master)

### E39. Avoid `to_sym` on user input, `String#@+`/`@-`, and other Ruby-version-dependent features — Portability
**Severity:** major
**Rule:** Stick to the Ruby version range your project supports. Don't use methods/syntax that only exist in a newer Ruby than the declared minimum.
**Why:** roda#306: "You cannot use `String#{@+,@-}` . Roda supports Ruby 1.9+." sequel#2288: "You should pass `opts` directly here (Sequel still supports Ruby 1.9)." This is a "respect the contract" rule — declared support range is binding.
**How to spot:** Feature use that requires a Ruby version newer than the gemspec / CI matrix advertises; "modern Ruby" idioms (`then`, `it`, pattern matching, `Data.define`) creeping into libs that target older Rubies.
**Examples:** [roda#306](https://github.com/jeremyevans/roda/pull/306#discussion_r1096822056), [sequel#2288](https://github.com/jeremyevans/sequel/pull/2288#discussion_r1997463219)

### E40. Test setups should fail loudly when wrong, not silently skip — Testing
**Severity:** major
**Rule:** When a test would only be meaningful under a specific dependency/environment, guard with a *fail or skip with reason* — never let it silently pass on the wrong setup.
**Why:** rodauth#264: "It seems worthwhile to run this unless `ENV['RODAUTH_NO_ARGON2']` is specified or argon2 is not available." Jeremy also has many commits adding "Skip the i18n related specs if the library is not installed, and just print a warning, similar to the other integrations." The pattern: skip explicitly, advertise the skip.
**How to spot:** Conditionals that early-return from tests without printing/skipping; tests that "pass" because the assertion is wrapped in a rescue; coverage of env-dependent code paths gated only by a silent `if`.
**Examples:** [rodauth#264](https://github.com/jeremyevans/rodauth/pull/264#discussion_r982925745)

### E41. Don't add "convenience" methods that hide unsafe defaults — API design
**Severity:** major
**Rule:** Avoid methods named `current_x` / global helpers that return ambient state with no auth check. If a method's return value is sensitive, name it loudly (e.g. `account!`) and require the caller to think.
**Why:** rodauth on a `current_account` proposal: "I think if we did have a method like this, we would want it to use `account_from_session`, not access the dataset directly. The documentation for the method also would need to be updated, since it will return an already set record for an account not logged in … I don't like the `current_account` name, mostly because of negative connotations with the way Rails uses `Current`, though I understand the reasons that rodauth-rails would want to use the name. I think `account!` may be an acceptable name, as the `!` indicates that the user should think twice before using it."
**How to spot:** `Current.user`, `current_account`, `current_*` helpers that return data with no explicit auth check; helpers that bypass the documented retrieval path.
**Examples:** [rodauth — current_account discussion](https://github.com/jeremyevans/rodauth/pulls)

### E42. Don't fight the standard library; fix the upstream issue — Style
**Severity:** major
**Rule:** When a Ruby/standard-library/Rack call doesn't behave as you want, prefer fixing the upstream cause to layering a workaround. Reach for monkey-patches and rescues last.
**Why:** forme#6: "You have a `to_s` method that returns a non-string? That's going to break a lot of libraries. I don't think I want to try to handle that. You should fix whatever code is creating the object so that `to_s` returns a string, or alternatively call `to_s` on the object before passing it to `h`." Sequel `Bignum` discussion: "This patch leads us down a slippery slope, where Sequel tries to undo changes in newer ruby versions to preserve the behavior in previous ruby versions. I don't want that. Sequel should respect the behavior of the current ruby version in use."
**How to spot:** Library code that special-cases broken inputs from another library; monkey-patches that work around an upstream bug instead of filing/fixing it; "compatibility shims" that aren't documented as such.
**Examples:** [forme#6](https://github.com/jeremyevans/forme/pull/6#issuecomment-39642058)

### E43. Use `instance_variable_set`/`get` (when you must reach in) over hacks — Style
**Severity:** major
**Rule:** When tests or framework code legitimately needs to set internal state, prefer `instance_variable_set` over reopening the class or relying on accessor side-effects.
**Why:** rodauth#265: "Seems better to use `instance_variable_set` here." Direct and explicit beats subtle.
**How to spot:** Test or setup code that calls a public method just for its side-effect on `@x`; injection that mutates state through indirection rather than directly.
**Examples:** [rodauth#265](https://github.com/jeremyevans/rodauth/pull/265#discussion_r983684319)

### E44. Don't add new tests by replacing existing ones — Testing
**Severity:** major
**Rule:** Adding a test for a new scenario should not delete the existing test. Keep coverage; add to it.
**Why:** rodauth#265: "Can we keep both current specs, and then add the spec you wrote as a new spec?"
**How to spot:** A PR that adds 1 spec and deletes 1 spec covering similar but distinct behaviour; "improved" tests where the diff shows a removal of coverage.
**Examples:** [rodauth#265](https://github.com/jeremyevans/rodauth/pull/265#discussion_r983685478)

### E45. Don't reset things to nil for "tidiness" — Performance
**Severity:** major
**Rule:** Don't allocate or assign just to keep things visually tidy. Don't recompute current timestamps/values when the existing branch never reads them.
**Why:** Sequel timestamps PR: "while the style is a little better, it hurts performance in the default case when create timestamp is already set, since your patch changes things to calculate the current timestamp in all cases, even when it would not be used. For that reason, I can't accept it." Same principle as E20/E21: don't pay for unobserved cleanliness.
**How to spot:** Refactors that compute values eagerly to "simplify" branches; setters called regardless of whether the value is used; `Time.now`/`SecureRandom.uuid` calls in code paths where the result is later thrown away.
**Examples:** [sequel — timestamp refactor discussion](https://github.com/jeremyevans/sequel/issues)

### E46. Don't silently change wire/serialization format — Compatibility
**Severity:** major
**Rule:** Output format (JSON shape, HTML attributes order, header values) is part of the contract. Changes that alter format need an explicit opt-in or a major-version note even if "the data is equivalent."
**Why:** forme bs5 commit: "I tried to reduce duplication a little bit by using `Forme.attr_classes` more in the bs5 support, but I found that broke the tests as it changed the order of classes in the output. I added a `Forme.attr_classes_after` method that allows the existing tests to pass." Order matters; people parse and snapshot output.
**How to spot:** Test goldens regenerated wholesale; serializers/formatters with rewritten body but new ordering; "cleaner" JSON that flips array/key order.
**Examples:** [forme — attr_classes_after commit](https://github.com/jeremyevans/forme/commits/master)

## Minor

### E47. Match the existing in-file style — Style
**Severity:** minor
**Rule:** New methods follow the file's conventions: parentheses on def, single-line ternaries where the rest of the file uses them, spacing around braces consistent with neighbouring methods.
**Why:** roda#5: "As a style issue, like all the other plugins, please use parentheses around arguments in a method definition, if there are arguments." rodauth#117: "Style-wise, I would prefer the ternary operator on a single line in this case." Style consistency reduces review noise.
**How to spot:** New code that diverges from immediately-adjacent style; mixed bracket/parenthesis usage in one file; inconsistent block-brace style within a class.
**Examples:** [roda#5](https://github.com/jeremyevans/roda/pull/5#discussion_r18006225), [rodauth#117](https://github.com/jeremyevans/rodauth/pull/117#discussion_r471120237)

### E48. Use `if block_given?` instead of a block param when you don't need a default — Style
**Severity:** minor
**Rule:** When yielding to an optional block, leave the explicit block argument off and use `yield ... if block_given?`.
**Why:** roda#5: "If you do want to do this, the preferred style is leaving the block argument off, and just use `yield opts if block_given?`."
**How to spot:** `def foo(&block); yield(x) if block; end` or `block.call(x) if block` patterns.
**Examples:** [roda#5](https://github.com/jeremyevans/roda/pull/5#discussion_r18005966)

### E49. Don't dup strings (or other immutables) "just in case" — Style
**Severity:** minor
**Rule:** Dup hashes and arrays that you'll mutate; don't dup strings unless you specifically need a mutable copy. "Anyone mutating strings deserves what they get."
**Why:** roda#5: "You'll probably want to dup the `:css`, `:js`, and `:headers` options as well. I don't consider it necessary to dup string values, as anyone mutating strings deserves what they get."
**How to spot:** `value.dup` on strings/symbols/integers; reflexive `.dup` on every option-hash value.
**Examples:** [roda#5](https://github.com/jeremyevans/roda/pull/5#discussion_r18006077)

### E50. Polite-but-firm review tone — Process
**Severity:** minor
**Rule:** When pushing back on a contributor, restate their goal, explain the tradeoff, offer the route you'd accept. Don't just say "no."
**Why:** Pattern across hundreds of Jeremy's replies. Even rejections come with "I could potentially consider X, if you wanted to do Y," "I'd be OK with this as an option, but not as the default," "this is fine as an external plugin, here's how to link it." This is a maintainer norm, not a rule about diffs.
**How to spot:** Review comments that say "no" with no path forward, or pile criticism without acknowledging the contributor's reasoning. Use this rule to remember to write better review comments, not to block PRs.
**Examples:** [roda#306 — extended dialogue](https://github.com/jeremyevans/roda/pull/306#discussion_r1093798854)

## Framework-specific (informational)

These rules are real patterns in Jeremy's commits/reviews but apply only inside Sequel/Roda/Rodauth/Forme. They are noted here so reviewers don't try to surface them on ubicloud diffs, but they do not load into the rule set walked by `/ubi-review`.

- **F1. Sequel association internals.** Many sequel commits ("Make `:many_to_one` associations support `:dataset`, `:order`, `:limit`", "Support `:lateral_subquery` as a filter by associations limit strategy", "Treat clob columns as strings instead of blobs") concern Sequel's association/dataset graph. The general lesson (caching strategies, eager-load strategies) does not translate.
- **F2. Roda plugin loading/cache architecture.** Commits like "Use RodaCache for the plugin cache", "Add Roda::RodaCache for a thread safe cache", "Raise error if using an invalid multi_route namespace when routing" are about Roda's per-class plugin-and-cache machinery.
- **F3. Rodauth feature wiring.** "Add `rodauth.possible_authentication_methods`", "Execute `get_block` and `post_block` in the `Rodauth::Auth` instance scope", "Refactor and simplify the jwt_refresh support" — Rodauth has its own DSL/instance model. The general principles (don't change defaults, scope tokens narrowly) are already captured above (E4, E28, E29); the wiring specifics aren't.
- **F4. Forme transformer/Tag/Input refactors.** Commits like "Decouple Tag and Input from Form", "Make error_handler, labeler, and wrapper take tag and input", "Add Form#each_obj" are about Forme's internal tag-tree model.
- **F5. Adapter-specific quirks.** "Handle JRuby 1.7 exception handling changes", "Force rack 2 when testing rack session support", "Move haml <5 travis gem guard", "Use Rack::Files instead of Rack::File if available" — sometimes the right answer is to special-case a specific dep/runtime combo. The meta-lesson (document the *why* in the commit body, see E10/E34) applies; the case itself doesn't.
- **F6. RDoc/website conventions.** "Update the documentation in `www/pages/documentation.erb`", "Use rdoc format, not Markdown for docs", "Add link to the external plugin section." These are Jeremy-project docs conventions, not general code review rules.

## Non-actionable (excluded)

Of the 5,434 conversation comments, the bulk are acknowledgements ("Thanks for the patch!", "Looks good, will merge", "Cherry-picked as `abc1234`"). Of the 10,273 commit messages, many are one-liners ("Update CHANGELOG", "Bump copyright year", "Test on ruby X on Travis", "Skip i18n tests on JRuby 9.2"). These were inspected but did not produce dedicated rules — the rule extraction looked for *repeated principles*. The commit-message *style* (terse imperative subject + reasoning body) is captured by E10. CI/Ruby-version maintenance is captured implicitly by E22/E25/E39.

Caveats:
- The 60 inline comments span only 12 PRs total; the bulk of the signal in this playbook comes from the conversation/summary/commit corpus.
- Several blocker-level rules (E5, E6, E29, E30) translate Ruby/web-stack security patterns; ubicloud uses Sequel and Roda, so most should fit cleanly. A handful of rules (E13, E14, E17) are about library API surface design — apply with judgement to ubicloud's internal APIs.
- The dataset has only 1 PR description from Jeremy; PR-framing patterns aren't represented strongly.
