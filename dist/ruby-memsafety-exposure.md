# Rails and Sinatra exposure review for the Ruby memory-safety fixes

> Single-file edition, generated from the multi-file skill. Paste it into an agent session opened in the application's repository, or tell the agent to read it and follow it.

Upgrading Ruby is the fix. This review answers two questions for one application: which affected surfaces an outsider can reach before the upgrade lands, and what the maintainer should do about each one. It reads code. It never tries to trigger a bug, and it contains nothing that would help someone do so.

## Two roots

This file is the whole procedure. The sections named "Reference" at the end are material the steps point to. It lives outside the application under review. Say which commit of the application you read.

Do not ask for what the request already gives you. Ask for the application's path, or for the fixed versions, only when the request leaves them out.

## What was fixed

| Surface | Step | What goes wrong | What an attacker needs | Advisory |
|---|---|---|---|---|
| Case conversion in a legacy encoding | 2a, 2b | A write past a buffer when certain case conversions run on a string in a legacy single-byte encoding | To choose a string's encoding and content | GHSA-34m4-m9fh-gqp5 |
| Case conversion on a very large string | 2c | A write past a buffer once the converted string passes 4 GiB, in any encoding | To get a string of about 1.3 GiB or more converted | GHSA-87fm-7w84-j2px |
| Regexp compilation | 3 | Memory corruption while a pattern is compiled | To supply the pattern | GHSA-7x2q-68qv-6p8x, GHSA-3p8q-wmhx-vm2w |
| Regexp to string | 4 | A write outside a buffer when a compiled regexp is turned back into a string | To supply the pattern, and the app or a gem to stringify it | GHSA-7whj-cfh7-xgm4 |
| Case-insensitive backreference | 5 | A read past the end of the string being matched | A pattern with both properties, and to supply the string | GHSA-pvgc-g7gj-pv6h |
| Match on a very large string | 6 | A double free when an allocation fails during a match | To supply a very large string, in a process whose allocations can fail | None of its own |
| Match in a non-UTF-8 encoding | 7 | Memory corruption during a case-insensitive match | To supply both the pattern and the string, in another encoding | GHSA-wpqw-5qxg-m68r |

The advisory is https://www.ruby-lang.org/en/news/2026/11/18/multiple-vulnerabilities-in-regexp-and-string/. CVE IDs had been requested but not assigned when it was published, so it names each fix by its GHSA ID. Take CVE IDs from the advisory, not from memory. The fix for step 6 has no advisory of its own and ships in the same releases.

| Branch | Fixed in |
|---|---|
| 4.0 | 4.0.10 |
| 3.4 | 3.4.13 |
| 3.3 | 3.3.14 |
| 3.2 and earlier | No fix. These branches have reached end of life |

## Ground rules

- Read-only on the application. No file changes, no requests to the app or its deployments, no reproduction. Fetching public gem source is fine. In a working development setup you may run commands that only boot the app, such as `bin/rails middleware`. The probe in the section "Optional probe for step 2" is the one exception to read-only, and only when the user asks for it.
- Judge the production configuration. Code that only runs in development or test is noted under Evidence and does not make a surface Exposed.
- Exposure is a conjunction. Each step names what must all be true. One false condition settles that surface, so check the cheapest condition first and stop there.
- Once a surface is Exposed at the lowest reach level, stop enumerating. Give up to three representative sites, and check that the action you will recommend closes them.
- A verdict rests on code you read. A control outside the repository (CDN, WAF, load balancer) can only lower a verdict. When every condition visible in the repository holds, the verdict is Exposed, and the outside control becomes a question. Use Unknown when the missing fact is one the verdict needs in order to be Exposed, such as the address-space limit in step 6. An example file (`*.example`, `*.sample`) shows a likely default, not the deployed value. Do not guess what is outside, and do not connect to a monitoring service, a cloud console or any other account to look it up, even when a connector for it is available. The person running the review may not have that access, and the review has to read the same for everyone. Write the exact command or question for the deployment owner instead.
- Name the framework. A Sinatra app mounted in a Rails app's routes runs behind the Rails middleware and then its own, so check both stacks.
- Gems to read at the locked version: rack; railties, actionpack and activesupport for Rails; sinatra, and padrino-core if locked, for Sinatra; cbor, webauthn, cose, the HTTP client the app uses, and a request sanitizer middleware if one is locked. The section "Where to look inside the gems" says where to look, what is already known, and how to get the source. When a string leaves the app into any other gem, the verdict for that path is Not exposed, and the gem goes under "Not verified". When a string comes back from such a gem and reaches an affected method or a regexp, read just enough of the gem to learn the encoding of what it returns. If you cannot tell, the verdict is Unknown.
- The section "Search recipes" has search patterns for steps 2, 3 and 5, with a separate one for 2c.
- If the repository holds several editions or trees, say which you read.
- Print one line of progress after each step, so a long review does not look stalled.

## Reach levels

Use one of these for every finding, lowest first.

1. Unauthenticated
2. No local account: content from a third-party server or sender, such as federation, a fetched URL or inbound mail
3. Any account. Say whether sign-up is open
4. Privileged: an admin or operator

The level is the least privilege that sets up every precondition. A passkey sign-in that needs a stored credential is "Any account", because the attacker registers their own. When one party picks the source and another controls the content, write both: "No local account, through a source an admin chose".

## Steps

### 1. Versions

Report each source separately: `.ruby-version`, `.tool-versions`, the `ruby` line in `Gemfile`, the RUBY VERSION section of `Gemfile.lock` and of any second lockfile, Dockerfiles, CI (every variant it runs). If the image is built from the repository, report its version and ask which build is running. If it is defined elsewhere, write "deployed version unknown". Report the locked versions of rails or sinatra (and padrino-core), rack, cbor, webauthn and cose.

The verdict here is Fixed, Not fixed or Unknown. If the deployed Ruby is fixed, nothing below is exposed. Say so first, and finish the remaining steps only if the user wants them.

### 2. Strings reaching case conversion

Two bugs share this step. 2a and 2b cover a string in a legacy single-byte encoding, at any length. 2c covers a very large string in any encoding.

For 2a and 2b the affected methods are `upcase`, `swapcase`, `casecmp?` and `downcase(:fold)`, with their bang forms. For `casecmp?` either operand counts. Plain `downcase`, `capitalize` and `casecmp` are not affected there. Reporting them buries the real findings. A string that is UTF-8, US-ASCII or binary is not affected by 2a and 2b, and neither is one that is restricted to ASCII, or cut to a few characters, before the call.

**2a. Request parameters.** Exposed only if Rack applies the declared charset, nothing overrides it, and an affected method runs on a parameter. Rack applies the charset declared on a multipart text part to that parameter. Rails only checks `valid_encoding?`, so the declared encoding reaches middleware and controllers unchanged. Sinatra re-tags top-level String parameters as UTF-8 when it dispatches, before filters and routes, but leaves values inside nested hashes and arrays (`user[name]`, `tags[]`) in the declared encoding, and middleware runs before the re-tagging. Anything mounted on the same Rack stack, such as an API framework, goes through the same parser. Check:

- whether `Rack::MethodOverride` is in the stack. It calls `upcase` on a parameter before authentication. Rails adds it unless `config.api_only`. Sinatra adds it for a classic app (the top-level DSL after `require "sinatra"`, or a subclass of `Sinatra::Application`) and for Padrino, and for a `Sinatra::Base` subclass only after `enable :method_override` or `set :method_override, true`. `use Rack::MethodOverride` in `config.ru` adds it to either. Check every app class that is mounted.
- middleware order. Validation middleware below `Rack::MethodOverride` does not protect it. If a sanitizer middleware is locked, see the section "Where to look inside the gems": the common ones skip multipart bodies.
- whether code loaded at boot (a Rails initializer, or a file that `config.ru` or the Sinatra app requires) overrides the part charset handling, a proxy or WAF rule restricts it, or a proxy that ships in the repository rewrites multipart bodies before Rack sees them.
- other code that calls an affected method on a parameter. This matters only when `Rack::MethodOverride` is absent. In Sinatra routes and filters, count nested hash and array values only. Top-level values are UTF-8 there, through `params` and `request.POST` alike.

**2b. Strings whose encoding someone else chooses.** Exposed only if a string enters in an encoding its sender chose, is still in that encoding later, and an affected method runs on it. Entry points are HTTP responses, files, CSV, mail and anything passed to `force_encoding` or `Encoding.find`. `CSV.new(string, encoding: "UTF-8")` keeps the string's own encoding, so that option does not make a call safe. Parsers and stores that return UTF-8 end the trail (see the section "Where to look inside the gems"). Background jobs that fetch from a third-party server are entry points with reach "No local account".

Work from the shorter list, because following every string has no end in a large codebase. List the entry points and the affected calls. If the calls are the shorter list, trace each receiver and argument back to where it came from. When every affected call is classified and none can receive a string in a sender-chosen encoding, 2b is Not exposed. If the entry points are the shorter list, start where the two lists share a file or a class, then follow each remaining entry point for two calls. If neither direction settles it, the verdict is Unknown and you offer the probe.

**2c. Very large strings, in any encoding.** The length of the converted string is counted in 32 bits, so once the output passes 4 GiB the result is written past its buffer. Exposed only if a string from outside, with at least one non-ASCII character, can reach one of these methods at the size shown, and no layer in the repository stops it first. UTF-8 counts here. A string that is ASCII only takes another path.

| Methods, with their bang forms | Smallest input that can trigger it |
|---|---|
| `upcase`, `swapcase`, `downcase(:fold)`, `casecmp?` (either operand) | 1.33 GiB in UTF-8, UTF-16 or UTF-32. 2 GiB in the single-byte encodings of 2a |
| `downcase`, `capitalize` | 2 GiB in UTF-16 or UTF-32. 2.67 GiB in UTF-8 |

Check:

- `Rack::MethodOverride`. It takes `_method` from URL-encoded and multipart bodies. Whether `_method` can reach the size above depends on the locked rack and on its environment variables (see the section "Where to look inside the gems"). Where it can, an unauthenticated POST reaches `upcase`.
- other parameters that reach one of these methods. A JSON body has no limit in Rack or Rails, so only the app server and the proxy bound a JSON parameter. Sinatra puts a JSON body into `params` only through middleware the app adds, so read that middleware for a limit.
- uploads, decompressed data, fetched documents, mail bodies or repository blobs held whole in one string and converted.
- the size limit at each layer, answered as in step 6. A limit below the smallest input closes the path.

The conversion holds the input and more than 4 GiB of output at once. With less memory the process fails on memory instead. That limit is outside the repository, so ask the owner, and keep the verdict the repository gives.

### 3. Regexps compiled from untrusted data

Exposed only if someone outside the team can decide the pattern. Classify each site instead of listing every match.

1. A pattern written by a user and compiled by Ruby. Exposed. List any guard next to it: a length cap, a timeout, a syntax check, a workaround for an earlier bug. None of these lowers the verdict, because the pattern still reaches Ruby's compiler. Only a different engine does: a pattern that only RE2 compiles is Not exposed.
2. A value that is escaped before use, whoever wrote it. `Regexp.union` escapes its String arguments. Not exposed here or in steps 4, 5 and 7. Give a count and one example.
3. A pattern written by an admin, or read from configuration. Exposed, reach Privileged, whatever the value is today. Say what the default is.
4. A constant. Do not report it.

Sites to look at: `Regexp.new`, `Regexp.compile` and `Regexp.union` with a non-literal argument, interpolated regexp literals (they can span lines), and `String#match` and `String#match?` given a String. Other String methods treat a String argument literally.

Deserializers that build Regexp objects from untrusted bytes: CBOR, YAML with Regexp permitted, Marshal. A cache or session store that only the application writes is trusted. For CBOR, check the locked cbor version first. Recent releases do not build a Regexp unless the caller opts in, and then CBOR is Not exposed and step 4 has nothing to read in webauthn or cose. Otherwise establish the reach level from the application's own flow, for sign-in and for registration: what must already be true before the gem decodes attacker bytes.

### 4. Regexps from step 3 turned into strings

Exposed only if step 3 found a Regexp object that outsiders control and that object is stringified: `to_s`, interpolation of the Regexp into a string or another regexp, `Regexp.union`, logging. Building a pattern string from user text is step 3, not this. `inspect` and `source` are not in scope. An error message in webauthn or cose that interpolates a decoded value counts.

### 5. Case-insensitive regexps with a backreference, applied to untrusted strings

Exposed only if the pattern has both properties and the string it is matched against comes from outside. A string comes from outside when an outsider chooses its content, even if a trusted party signed or relayed it, such as a claim in a verified token. Look at the pattern side only. `\1` in a `gsub` replacement string is not a backreference in a pattern.

- A constant pattern with both properties: Exposed, with the reach of whoever supplies the string.
- A class 1 pattern from step 3 that Ruby compiles case-insensitively, or where the author can add the flag: Exposed, with the reach of whoever writes the pattern.
- A class 3 pattern matched against text from a lower reach level: Unknown, with the reach of whoever supplies the text. It depends on the patterns stored, so ask the owner whether any stored pattern has a backreference.

For dependencies, check only the ones in the section "Where to look inside the gems", and only if they load in production.

### 6. Size limits

The allocation that can fail grows with the length of the string, so there is no exact size. Use 1 MiB as the working line.

Count matches in the application's own code. A match inside a gem is out of scope.

- Not exposed: nothing in the repository lets an untrusted string above that line reach a regexp match.
- Exposed: such a string can reach a match, and the process runs under an address-space limit (`RLIMIT_AS`, `ulimit -v`, systemd `LimitAS`). A limit makes this worse, not better. It is what lets the allocation fail.
- Unknown: such a string can reach a match, and no address-space limit is visible. Ask the owner, for each kind of process that runs the match (web, job workers). A cgroup memory limit or an RSS watchdog is a different mechanism. Report it, and leave the verdict Unknown.

To find the largest string, answer per layer: proxy, CDN or WAF (Unknown unless configured in the repository), a WAF that runs inside the app, a proxy that ships in the repository in any language, the app server, Rack, the application. For each, say whether the limit counts bytes received or trusts `Content-Length`. Body parameters are parsed for any HTTP method, so a route that only answers GET still receives them. Defaults are in the section "Where to look inside the gems". Then look for code that holds a whole body or file in one string and matches it: middleware that scans bodies, mail bodies, parsed uploads, repository blobs, CI logs, fetched documents.

### 7. Regexps in another encoding

Exposed only if a class 1 pattern from step 3 is matched case-insensitively, and the pattern itself can reach the compiler in an encoding its sender chose. That needs the pattern to come straight from a string found in 2a or 2b. A pattern that is stored and read back from a UTF-8 database, or that arrives as JSON or as a URL-encoded parameter, is UTF-8 by then.

A pattern the application wrote does not count, even though Ruby compiles an ASCII pattern again in the encoding of the string it is matched against. Fixed ASCII patterns were tested against strings in such encodings and did not trigger the bug (see the section "Where to look inside the gems"). The same holds for a class 3 pattern, unless the admin can supply it in another encoding.

The actions that close 2a and 2b close this step for the same strings.

## Report

Before writing, read the section "Checks and common misjudgments" and run its checks against your findings. The section "Example report" shows a finished report.

Put one line under the title: `Action needed: Yes`, `No` or `Unknown`. It is No when step 1 is Fixed. Otherwise it follows the worst verdict among the other steps: Yes for Exposed, Unknown for Unknown, No when every one is Not exposed.

Lead with what to do. A maintainer who reads only the first section should know their next three actions. Pick actions from the section "Actions", name the step each one closes, and order them by reach level.

Give one verdict per surface: Exposed, Not exposed or Unknown. "Probably exposed" is not a verdict. When parts of a surface differ, the worst wins (Exposed, then Unknown, then Not exposed), with the part in parentheses: "Exposed (user-written patterns only)". For an Unknown row, give the reach it would have if exposed.

Keep the headings and the verdict words in English, so reports can be compared. Write the rest in the user's language. Leave out the CVE column until the IDs exist.

```markdown
# Ruby memory-safety exposure: <app> at <commit>

Action needed: Yes / No / Unknown

## What to do
1. Upgrade Ruby to <the fixed release for the branch, or 3.3.14 or later from 3.2 and earlier>. Found: <versions and where>.
2. <action> closes step <n>. <where to apply it>.

## Verdicts
| Step | Surface | Verdict | Reach |
|---|---|---|---|
| 1 | Ruby version | Fixed / Not fixed / Unknown | n/a |
| 2a | Request parameters reaching case conversion | Exposed / Not exposed / Unknown | <level> |

## Evidence
### Step 2a
- path/to/file.rb:12 what it shows

## Ask the deployment owner
- <what the repository cannot answer>: run `<exact command>` on <where>. <which answer means what>.

## Not verified
- <what you did not check, and why>
```

Keep the table to verdict and reach. Evidence goes in the per-step sections with file:line. "Not verified" is required even when it is short.

## Reference: Where to look inside the gems

Search for the symbol. File names differ between releases, and line numbers always do. Each fact below names the versions it was checked on. Confirm it in the locked version before relying on it.

### Getting the source

1. List the gem directories: `gem env` prints them under GEM PATHS. Search them with `find <dir> -maxdepth 2 -name '<gem>-*'`, not with shell globs.
2. `bundle show <gem>` is quicker when it works. It fails when the running Ruby differs from the one in the Gemfile, or when the version manager's configuration is not trusted.
3. If the locked version is not installed, look for `<gem>-<version>.gem` in the `cache` directory of a gem path and run `gem unpack` on it into a temporary directory. Otherwise `gem fetch <gem> -v <version>` and then `gem unpack`.
4. Say which version you read. If it is not the locked one, say so.

### Step 2a: request parameters

| Gem | Symbol | What to confirm |
|---|---|---|
| railties | `default_middleware_stack.rb` | `Rack::MethodOverride` is added unless `config.api_only` |
| rack | `Rack::MethodOverride#method_override` | Runs only for POST. Takes `_method` from the body, or the `X-HTTP-Method-Override` header when the body has none, and calls `upcase` |
| rack | `tag_multipart_encoding` in `multipart/parser.rb` | A text part without a filename gets the encoding its `charset` names |
| actionpack | `check_param_encoding` in `request/utils.rb` (7.2), `http/param_builder.rb` (8.0 and later) | Parameters are checked with `valid_encoding?` and not transcoded |
| rack-sanitizer, rack-utf8_sanitizer | `SANITIZABLE_CONTENT_TYPES` | Multipart is not in the default list (rack-sanitizer 2.1.0, rack-utf8_sanitizer 1.11.1) |
| sinatra | `setup_default_middleware` and `set :method_override` in `base.rb` | `Rack::MethodOverride` is added when `method_override?` is true. It is false on `Sinatra::Base` and true on `Sinatra::Application`. `methodoverride` is an alias |
| sinatra | `dispatch!` in `base.rb` | Top-level String parameters are re-tagged in place as `default_encoding` (UTF-8). Hash and Array values are skipped |
| padrino-core | `application_setup.rb` | `set :method_override, true` (0.18.5) |

The Sinatra rows were run on sinatra 2.0.8.1, 2.2.4, 3.2.0, 4.0.0 and 4.2.1 with rack 2.2.23, 3.0.11 and 3.2.8, using multipart parts that declare ISO-8859-1. `Rack::MethodOverride` received the declared encoding in a classic app and in a `Sinatra::Base` subclass with the setting on, and nowhere else. Routes saw top-level values as UTF-8 and nested hash and array values as ISO-8859-1. Releases before 2.0.6 re-tag nested values too (read, not run). rack-protection calls no affected method on request data (4.2.2).

A part charset that is not ASCII-compatible (UTF-16, UTF-32) never reaches the application through parameters. The part's name carries the same encoding, and `Rack::QueryParser#normalize_params` (2.2) or `#_normalize_params` (3.x) raises on it. Checked on rack 2.2.23, 3.0.18, 3.1.22 and 3.2.8. ASCII-compatible charsets are applied.

Puma and WEBrick hand header values over as binary strings, so the `X-HTTP-Method-Override` header does not carry a chosen encoding.

### Step 2b: who sets the encoding of fetched data

| Gem | Symbol | Behaviour |
|---|---|---|
| faraday-net_http | `encoded_body` | Applies the charset from the response Content-Type (3.5.0) |
| http | `HTTP::Response::Body` | Applies the response charset to what it reads (6.0.4) |
| httparty | `text_encoder.rb` | Applies the response charset, including UTF-16 (0.24.3) |
| net-http | `response_body_encoding` | Leaves the body binary unless this is set (0.10.0) |

These end the trail, because what they return is UTF-8:

- `JSON.parse` and YAML loading.
- ActiveRecord attributes read from a database whose connection encoding is UTF-8. Check `encoding` in `config/database.yml`. Binary columns are the exception.
- Text and attribute values from Nokogiri, including `Attr#to_s` and `NodeSet#to_s` (1.19.7). Serializing a document or an element (`to_html`, `to_xml`, `to_s` on those) follows the document's encoding instead.

### Step 3 and 4: CBOR

Check the version first. From cbor 0.6.2.2, tag 35 decodes to a `CBOR::Tagged` unless the caller passes `reconstruct_from_tags`. webauthn 3.5.1 and cose 1.4.0 require that release. If the locked cbor is 0.6.2.2 or later and no caller opts in, CBOR is Not exposed and the rest of this section can be skipped.

For older cbor (checked on 0.5.10.3 and 0.6.1.1, with webauthn 3.5.0 and cose 1.3.1):

| Gem | Symbol | What to confirm |
|---|---|---|
| cbor | `TAG_RE` in `ext/cbor/unpacker.c` | Tag 35 is turned into `Regexp.new(text)` during decoding |
| webauthn | `AuthenticatorData#extension_data` | Extension data is decoded with `CBOR.decode` when `valid?` runs |
| webauthn | `AttestedCredentialData`, `public_key_length` | Credential data is decoded on the same path, also during sign-in when the flag for it is set |
| webauthn | `AuthenticatorResponse#verify` | Authenticator data is validated before the signature |
| cose | `key.rb`, `key/ec2.rb`, `key/okp.rb` | Error messages interpolate decoded values |
| webauthn | `attestation_statement.rb` | The unsupported-format error interpolates the decoded format |

The gem decodes before it verifies, but the application decides when the gem is called. Read the sign-in and the registration controllers: some apps look up the credential ID first, some run WebAuthn only as a second factor.

### Step 7

Ruby compiles a regexp again in the encoding of the string it is matched against when the pattern is ASCII-only and the string has non-ASCII characters in an ASCII-compatible encoding (`rb_reg_prepare_enc` in `re.c`). Fixed ASCII-only case-insensitive patterns were matched against valid strings in Emacs-Mule and stateless-ISO-2022-JP on Ruby 4.0.9, about 13,000 combinations each, and none crashed. A pattern written in those encodings does.

### Step 5: dependencies with such patterns

First check that the gem loads in production: its Bundler group, `require: false`, and whether it is only a dependency of a development tool. If it does not, stop.

- haml: `find_and_preserve` (`helpers.rb` in 5.x, `preserver.rb` in 7.x). It runs only where a template uses `~` or calls `find_and_preserve`. An app that renders with hamlit does not use it.
- rouge: the lasso and php lexers.

Report them as Unknown with the reach of the text they process. Other dependencies are out of scope.

### Step 2c and 6: limits

Rack. Each can be changed by the environment variable named, so look for it in the Dockerfile, the process manager and any committed environment file. A release older than the one listed has no such limit. Checked on the release tags of each line.

| Limit | Default | Variable | From |
|---|---|---|---|
| Whole multipart body, counted in bytes read | 10 GiB | `RACK_MULTIPART_PARSER_BYTESIZE_LIMIT` | 2.2.23, 3.1.21, 3.2.6 |
| Multipart parts that are not files, added together | 16 MiB | `RACK_MULTIPART_BUFFERED_UPLOAD_BYTESIZE_LIMIT` | 2.2.19, 3.1.17, 3.2.2. Never in 3.0 |
| URL-encoded body or query string | 4 MiB | `RACK_QUERY_PARSER_BYTESIZE_LIMIT` | 2.2.14, 3.0.16, 3.1.14 |

For 2c this means `_method` stays below the smallest input on rack 2.2.19, 3.1.17, 3.2.2 or later with the defaults. On 3.0, or on an older release of another line, a multipart body carries it at any size.

A JSON body has no limit in Rack or Rails. Only the server and the proxy bound it.

Puma: `http_content_length_limit` is unset by default. When set, it is compared with `Content-Length` and, for chunked bodies, with the bytes received.

nginx: `client_max_body_size`. Report the value per location, and whether any location sets it to 0.

## Reference: Search recipes

Starting points, not proofs. Each one over-matches, and none sees a construct that spans lines. Adjust the path list to the repository. A Sinatra app often keeps its code at the top level, so use `'*.rb'` there instead of `app lib config`. None uses `\b`, which `git grep -E` ignores on macOS.

### Step 2: affected case conversions

```bash
git grep -n -E '\.(upcase|swapcase)!?([^_a-zA-Z]|$)|casecmp\?|downcase!?\(:fold' -- app lib config
```

### Step 2a: method override in Sinatra

```bash
git grep -n -E "method_?override|Rack::MethodOverride|Sinatra::(Application|Base)|require ['\"]sinatra['\"]|Padrino" -- '*.rb' '*.ru'
```

A top-level `require "sinatra"` or a subclass of `Sinatra::Application` means the setting is on unless a `disable` follows.

### Step 2c: large data held in one string

Start from the inputs, because plain `downcase` and `capitalize` count here and they are everywhere:

```bash
git grep -n -E '\.(read|download|inflate)([^_a-zA-Z]|$)|Zlib::|Gzip|File\.(bin)?read|\.body\.to_s' -- app lib config
```

Then check whether an affected method, including plain `downcase` and `capitalize`, runs on what each returns.

### Step 2b: where an encoding is chosen

```bash
git grep -n -E 'Encoding\.find|String\.new\([^)]*encoding:|force_encoding|\.encode\(|response_body_encoding' -- app lib config
```

### Step 3: regexps that are not constants

Calls with a non-literal argument, without the escaped ones:

```bash
git grep -n -E 'Regexp\.(new|compile|union)\(' -- app lib config | grep -v -E 'Regexp\.(new|compile|union)\(["/%]' | grep -v -E 'Regexp\.(escape|quote)'
```

Interpolated literals, without the escaped ones:

```bash
git grep -n -E '(/|%r.)[^/]*#\{' -- app lib config | grep -v -E 'Regexp\.(escape|quote)'
```

`match` and `match?` given something other than a regexp literal:

```bash
git grep -n -E '\.match\??\([a-z_@]' -- app lib config
```

### Step 5: case-insensitive patterns with a backreference

```bash
git grep -n -E '/[^/]*\\(k<|[1-9])[^/]*/[a-z]*i' -- app lib config
git grep -n -E 'IGNORECASE|\(\?[a-z]*i' -- app lib config
```

The first finds literals. The second finds patterns made case-insensitive in other ways. Read each hit for a backreference on the pattern side.

## Reference: Actions

Every report starts with A. The others are interim measures. Each one closes an entry point, not the bug, so none of them replaces the upgrade.

| Action | Use when | Closes |
|---|---|---|
| A. Upgrade Ruby | Always | Everything |
| B. Ignore the charset declared on multipart parts | 2a is Exposed | 2a, and 7 for patterns that arrive as parameters |
| C. Reject multipart text parts that declare a charset other than UTF-8 or US-ASCII, at the proxy or WAF. The section "WAF and proxy rule for step 2a" has the rule and how to check it | 2a is Exposed. Use it with B, or alone until B ships | 2a, within the body size the edge inspects |
| D. Stop CBOR from building regexps: update cbor to 0.6.2.2 or later, or add the initializer | The locked cbor is older than 0.6.2.2 and untrusted CBOR is decoded | The CBOR part of 3 and 4 |
| E. Cap request bodies by bytes received, and cap input length before case conversion or matching | 2c or 6 is Exposed or Unknown | 2c and 6 |
| F. Rewrite the regexp: drop the case-insensitive flag or the backreference | 5 is Exposed for a pattern the app owns | 5 |
| G. Convert to UTF-8, or reject, where the data enters | 2b is Exposed | 2b, and 7 for the same data |
| H. Restrict who can write patterns, cap pattern length, or compile user patterns with another engine such as RE2. Remove Regexp from the classes YAML may load | 3 reports class 1 or 3 | Another engine closes 3, 4, 5 and 7 for the patterns moved to it. The rest only narrows them |
| I. Update rack to 2.2.19, 3.1.17, 3.2.2 or later, and leave `RACK_MULTIPART_BUFFERED_UPLOAD_BYTESIZE_LIMIT` and `RACK_QUERY_PARSER_BYTESIZE_LIMIT` at their defaults. The 3.0 line has no such release, so move to 3.1 or later | 2c is Exposed through `Rack::MethodOverride` or another URL-encoded or multipart parameter | 2c for those parameters. JSON parameters need E |
| J. Turn method override off where nothing sends `_method`: `disable :method_override` in a Sinatra app, or remove `use Rack::MethodOverride` from `config.ru`. Search the views and JavaScript for `_method` first. Rails form helpers send it, so this rarely fits a Rails app | 2a or 2c is Exposed through `Rack::MethodOverride` | 2a and 2c for `_method`. Other parameters still need B, C or I |

C is a second layer, not a replacement for B. A WAF inspects only the first part of a body and blocks some legitimate clients, and B has neither problem.

B and C do not close 2c. They stop the declared charset, and 2c needs none.

### B. Ignore the charset declared on multipart parts

Parameters keep Rack's default encoding. Credit: Ada Logics, who attached this initializer to their report.

```ruby
# config/initializers/ignore_multipart_part_charset.rb
require "rack/multipart/parser"

module IgnoreMultipartPartCharset
  private

  def tag_multipart_encoding(filename, _content_type, name, body) = super(filename, nil, name, body)
end

Rack::Multipart::Parser.prepend(IgnoreMultipartPartCharset)
```

A Sinatra app has no initializer directory. Require the same file from `config.ru`, or from the app file, before the app serves a request. Checked on sinatra 4.2.1 with rack 3.2.8, where it also closed nested hash and array values.

### D. Stop CBOR from building regexps

Prefer the update. cbor 0.6.2.2 no longer builds a Regexp from tag 35 unless the caller opts in, and webauthn 3.5.1 and cose 1.4.0 require it, so `bundle update webauthn cose cbor` is usually enough. Use the initializer when the update has to wait.

Older cbor calls `Regexp.new` through method dispatch, so a guard on `Regexp.new` that is active only during a decode stops tag 35 and leaves every other caller alone. The error is a `CBOR::MalformedFormatError`. Rescue `CBOR::UnpackError` where a 400 is wanted.

```ruby
# config/initializers/cbor_reject_regexp_tag.rb
require "cbor"

module CBORRejectRegexpTag
  KEY = :cbor_reject_regexp_tag

  class Error < CBOR::MalformedFormatError; end

  def self.with(state)
    prev = Thread.current[KEY]
    Thread.current[KEY] = state
    yield
  ensure
    Thread.current[KEY] = prev
  end

  module RegexpNew
    def new(*, **)
      raise Error, "CBOR tag 35 (regular expression) is not accepted" if Thread.current[KEY]
      super
    end
  end

  module ModuleFunctions
    def decode(*) = CBORRejectRegexpTag.with(true) { super }
    def unpack(*) = CBORRejectRegexpTag.with(true) { super }
    def load(*) = CBORRejectRegexpTag.with(true) { super }
  end

  module Unpacker
    def read = CBORRejectRegexpTag.with(true) { super }
    def unpack = CBORRejectRegexpTag.with(true) { super }

    def each(&block)
      return super unless block
      CBORRejectRegexpTag.with(true) { super { |obj| CBORRejectRegexpTag.with(false) { block.call(obj) } } }
    end

    def feed_each(data, &block)
      return super unless block
      CBORRejectRegexpTag.with(true) { super(data) { |obj| CBORRejectRegexpTag.with(false) { block.call(obj) } } }
    end
  end
end

Regexp.singleton_class.prepend(CBORRejectRegexpTag::RegexpNew)
CBOR.singleton_class.prepend(CBORRejectRegexpTag::ModuleFunctions)
CBOR::Unpacker.prepend(CBORRejectRegexpTag::Unpacker)
```

Checked with cbor 0.5.10.3 and 0.6.1.1, webauthn 3.5.0 and cose 1.3.1 on Ruby 4.0.9. It also loads on cbor 0.6.2.2, where it refuses a caller that opts in.

## Reference: WAF and proxy rule for step 2a

Use this when 2a is Exposed. It works alongside action B, and on its own until B ships. It covers request parameters only. It does nothing for steps 2b to 7.

### What to block

A multipart request in which a part without a filename declares `Content-Type: text/plain` with a `charset` other than UTF-8 or US-ASCII.

Write it as an allowlist. Rack accepts many spellings of the same header, and a rule that lists the charsets to block has to anticipate every one of them. A rule that lets two values through does not.

Two more rules of thumb:

- Match what Rack parses, not what browsers send. Charset names are case-insensitive, quotes are optional, whitespace around `=` and `;` is ignored, and from rack 3.1 a header line can be folded.
- A WAF inspects only the first part of a body. Reject multipart bodies larger than that limit on paths that do not take uploads, or the part can be placed beyond what the rule sees.

### The rule

This is a regular expression for the request body, applied after lowercasing. It uses no lookahead, backreference or possessive quantifier, so it fits the restricted dialects WAFs accept.

```text
content-type:[^a-z]*text/plain(?:[^\r\n]|\r\n[ \t])*;[^=;a-z0-9]*charset[^=;a-z0-9]*=[^a-z0-9";]*"?(?:[a-tv-z0-9]|u[^ts]|us[^-]|ut[^f]|utf[^-]|utf-[^8]|utf-8[a-z0-9_-])
```

It was checked against Rack's real parser on rack 2.2.23, 3.0.18, 3.1.22 and 3.2.8: every part header that Rack honours matched. The check script ships with the multi-file skill.

Two legitimate kinds of request match and will be blocked:

- Apache HttpClient 4 sends `charset=ISO-8859-1` on text parts by default.
- A multipart body that carries raw mail, such as an inbound mail webhook or an uploaded `.eml` file, when the mail has a text part in another charset.

Exclude the paths that receive these, or change those clients to send UTF-8.

### AWS WAF

Use two rules in the web ACL. The first is a regex match on the body with the LOWERCASE text transformation and oversize handling CONTINUE. The second blocks multipart bodies above the inspection limit: a size constraint on the body with oversize handling MATCH, combined with a `content-type` header that contains `multipart/`, and excluding the paths that take uploads. The limit is 8192 for an Application Load Balancer, and the configured value (16384 to 65536) for CloudFront, API Gateway and the others. A generator for the rule JSON ships with the multi-file skill.

These rules were checked against Rack, not on a live web ACL. Deploy them in count mode first.

### Other products

Translate the condition above. If the product accepts PCRE-style expressions on the body, check your expression against Rack's parser before deploying it.

### What to tell the user

In the report, action C names the product when the repository shows one (Terraform, CDN configuration) and states its body inspection limit if you know it. Mention the two kinds of legitimate request above only for an endpoint where the repository shows such a client or such content. Do not guess which endpoints they might hit.

## Reference: Optional probe for step 2

Static reading sometimes cannot tell whether a string in another encoding really reaches an affected method. This probe answers it by observation. It is the one exception to read-only, so use it only when the user asks for it, only in development or test, and delete it afterwards.

In a Rails app it goes in `config/initializers`. In a Sinatra app, require it from `config.ru` or the test helper before the app loads.

It prints a line whenever `upcase`, `swapcase`, `casecmp?` or `downcase(:fold)` runs on a string that is not UTF-8, US-ASCII or binary. Run the test suite or exercise the feature, then read stderr. A line is evidence for 2a or 2b, with the call site. Silence only means the paths exercised did not reach it. It does not help with 2c, which depends on size, not encoding.

```ruby
# config/initializers/zz_case_conversion_probe.rb (delete after the review)
module CaseConversionProbe
  QUIET = [Encoding::UTF_8, Encoding::US_ASCII, Encoding::BINARY].freeze

  def self.report(str, name)
    return if QUIET.include?(str.encoding)
    warn "[case conversion probe] #{name} on #{str.encoding}: #{caller(2, 8).join(" | ")}"
  end

  %i[upcase upcase! swapcase swapcase! casecmp?].each do |name|
    define_method(name) do |*args|
      CaseConversionProbe.report(self, name)
      super(*args)
    end
  end

  %i[downcase downcase!].each do |name|
    define_method(name) do |*args|
      CaseConversionProbe.report(self, "#{name}(:fold)") if args.include?(:fold)
      super(*args)
    end
  end
end

String.prepend(CaseConversionProbe)
```

## Reference: Checks and common misjudgments

### Checks before delivering

| # | Check | Passes when | If it fails |
|---|---|---|---|
| 1 | Fixed versions came from the advisory or the request | The source is named, or step 1 is Unknown | Mark step 1 Unknown |
| 2 | Each Ruby version source is reported separately | `.ruby-version`, `.tool-versions`, `Gemfile`, every lockfile, Dockerfile and every CI variant each have a line, or "not present" | Add the missing ones |
| 3 | Every verdict is Exposed, Not exposed or Unknown, and step 1 is Fixed, Not fixed or Unknown | No "likely" or "possibly" | Decide, or move it to Unknown with the reason |
| 4 | Every Exposed row has a reach level and file:line evidence | Nothing rests on a gem's reputation or a README | Read the code |
| 5 | Each Exposed row meets the condition its step states | The conditions are quoted against the evidence | Downgrade the row |
| 6 | Gem claims name the version read | The version equals the locked one, or the difference is stated | Read the locked version |
| 7 | "Action needed" sits under the title and matches the table, then "What to do" follows and each item names the step it closes | A reader can act without reading further | Rewrite the section |
| 8 | Unknowns have an exact command or question for the deployment owner | No bare "check your WAF" | Write the command |
| 9 | "Not verified" is present | It lists what was skipped and why | Add it |

### Common misjudgments

| Symptom | Cause | Correction |
|---|---|---|
| 2a marked Not exposed because a sanitizer middleware is installed | The sanitizers skip multipart bodies by default, and may sit below `Rack::MethodOverride` | Read `SANITIZABLE_CONTENT_TYPES` and the middleware order |
| 2a marked Not exposed because no controller uses `_method` | `Rack::MethodOverride` reads it for every POST | Check whether the middleware is in the stack |
| 2a marked Exposed for a modular Sinatra app because Sinatra uses `Rack::MethodOverride` | `Sinatra::Base` leaves it off. Classic apps, Padrino and apps that enable or `use` it have it | Check the base class, the setting and `config.ru` for each mounted app |
| 2a marked Not exposed for a Sinatra app because routes see UTF-8 parameters | `Rack::MethodOverride` runs before Sinatra re-tags them, and nested hash and array values are never re-tagged | Check the middleware first, then affected calls on nested values |
| An affected call on a top-level `params` value in a Sinatra route reported under 2a | Sinatra has re-tagged it as UTF-8 by then | Keep it only for nested values or for code that runs in middleware |
| Hundreds of call sites listed under 2a | Enumeration continued after the verdict was settled | Stop at three representative sites |
| Findings for `downcase`, `capitalize` or `casecmp` under 2a or 2b | They share a grep with the affected methods | Keep only `upcase`, `swapcase`, `casecmp?` and `downcase(:fold)` there. Plain `downcase` and `capitalize` count only under 2c |
| 2c marked Not exposed because B or C is in place, or because the strings are UTF-8 | 2c needs no declared charset, and size decides it, not encoding | Compare the largest string with the table in 2c |
| 2c marked Not exposed because Rack caps parameters | JSON bodies have no Rack limit, and the 3.0 line has no cap on multipart parts | Check each body type, the locked rack and its environment variables |
| CSV input treated as UTF-8 because of `encoding: "UTF-8"` | With a String source the string's own encoding wins | Trace where the string came from |
| 2b empty although the app fetches remote content | Only `force_encoding` and `encode` were searched | Read the HTTP client's charset handling, and follow background jobs |
| 2b Unknown for everything in a large codebase | Every string was followed without an order | Start where entry points and affected calls share a file, then offer the probe |
| Step 3 lists hundreds of sites | Every `Regexp.new` was listed | Classify, and drop constants |
| Step 3 includes `split`, `sub`, `scan` or `index` with a String | Only `match` and `match?` compile a String argument | Remove them |
| The CBOR flow was traced and then turned out not to matter | The gem version was checked last | Check the locked cbor version first |
| CBOR reach reported as Unauthenticated without reading the controller | The gem decodes before verifying, but the app decides when the gem runs | Find what the app looks up first, for sign-in and for registration |
| Step 4 lists strings built from user text | A pattern string is not a Regexp object | Keep only stringified Regexp objects |
| Step 4 empty although old cbor is decoded | Only application code was searched | Read the cose and webauthn error paths |
| Step 5 lists `gsub` replacement strings | `\1` was searched without telling pattern from replacement | Keep the pattern side only |
| Step 7 marked Exposed because `blank?` or `present?` runs on a UTF-16 string | That pattern is fixed | Step 7 needs a pattern an outsider wrote |
| Step 7 marked Exposed through multipart parameters in UTF-16 or UTF-32 | Rack raises on charsets that are not ASCII-compatible | Only ASCII-compatible charsets reach the application this way |
| Step 7 marked Exposed or Unknown because a fixed case-insensitive pattern meets a string in another encoding | Ruby does compile the pattern again in that encoding, but the bug needs non-ASCII bytes in the pattern | Only a class 1 pattern counts |
| Step 7 marked Exposed for a class 1 pattern that is stored first | It is UTF-8 when it is read back | Check where the pattern string comes from at the moment it is compiled |
| 2a marked Unknown because a CDN or WAF sits in front | An outside control can only lower a verdict | Mark it Exposed and ask the owner |
| An example configuration file reported as the deployed setting | It shows a default, not what runs | Ask the owner |
| A proxy or WAF limit stated without a file | It was assumed | Mark it Unknown and ask |
| An RSS watchdog or a container memory limit reported as an address-space limit | They are different mechanisms | Report them separately, and leave step 6 Unknown |
| A development-only path reported as Exposed | The environment was not considered | Judge the production configuration |
| Step 1 answered from `.ruby-version` alone | CI, the lockfiles and the image can each differ | Report every source |

## Reference: Example report

````markdown
> **This report is fictional.** Lantern is not a real application. Every path, commit and version below is invented. Take fixed Ruby versions from the advisory, never from here.

# Ruby memory-safety exposure: Lantern at 3f9c2a1

Action needed: Yes

## What to do

1. Upgrade Ruby to the fixed 3.4 release. Found: the same 3.4 release in `.ruby-version` and the Dockerfile, below the fix. This is the only action that closes everything.
2. Add the initializer that ignores multipart part charsets (action B). Closes 2a, which is reachable without authentication.
3. Convert fetched link previews to UTF-8 on arrival (action G) in `app/services/link_preview.rb`. Closes 2b, reachable by any account that posts a link. Sign-up is open.
4. Set `http_content_length_limit` in `config/puma.rb` above the 50 MiB upload limit (action E). Closes 2c for the JSON API, reachable by any account.
5. Run `bundle update webauthn cose cbor` (action D). Closes the CBOR part of 3 and 4, reachable by any account with a registered passkey.
6. Move the saved-search patterns to RE2, or reject backreferences when a search is saved (action H). Closes 3 and 5 for that feature.
7. Ask the deployment owner the questions below. Steps 2c and 6 depend on the answers.

## Verdicts

| Step | Surface | Verdict | Reach |
|---|---|---|---|
| 1 | Ruby version | Not fixed | n/a |
| 2a | Request parameters reaching case conversion | Exposed | Unauthenticated |
| 2b | Other strings reaching case conversion | Exposed | Any account |
| 2c | Very large strings reaching case conversion | Exposed (JSON API only) | Any account |
| 3 | Regexps compiled from untrusted data | Exposed (saved searches, CBOR) | Any account |
| 4 | Those regexps turned into strings | Exposed (CBOR only) | Any account |
| 5 | Case-insensitive backreference | Exposed (saved searches only) | Any account |
| 6 | Match on a very large string | Unknown | Any account |
| 7 | Regexps in another encoding | Not exposed | n/a |

## Evidence

### Step 1
- `.ruby-version:1` and `Dockerfile:1` name the same 3.4 release. No `.tool-versions`, no `ruby` line in `Gemfile`, no RUBY VERSION section in `Gemfile.lock`. CI reads `.ruby-version`.

### Step 2a
- `config/application.rb` does not set `api_only`, so `Rack::MethodOverride` is in the stack (railties, read at the locked version).
- No initializer touches `Rack::Multipart::Parser`. No sanitizer middleware is locked. No proxy configuration in the repository.
- Three more sites call `upcase` on a parameter. Action B covers them, because it removes the declared encoding before any of them runs.

### Step 2b
- `app/services/link_preview.rb:58` fetches with faraday. The locked faraday-net_http applies the charset the remote server declared.
- `app/services/link_preview.rb:91` calls `casecmp?` on the first line of that body, in the same class.
- The rest of the body goes to Nokogiri, which returns UTF-8.

### Step 2c
- rack is locked at 3.1.19, which caps URL-encoded bodies and multipart parts that are not files. No environment variable raises either limit, so `_method` stays below the smallest input.
- `app/controllers/api/labels_controller.rb:21` calls `upcase` on `params[:name]`, which arrives in a JSON body. Rack and Rails do not limit JSON, and Puma sets no `http_content_length_limit` (see step 6).
- The link previews of 2b are cut to 5 MiB at `app/services/link_preview.rb:60`, below the smallest input.

### Step 3
- Class 1: `app/models/saved_search.rb:31` compiles a user-written pattern with `Regexp.new(pattern, Regexp::IGNORECASE)`. Guards: a 200-character cap at `:12`. No timeout, no syntax check.
- Class 2: 9 sites, for example `app/models/tag.rb:44` with `Regexp.escape`.
- CBOR: cbor is locked below 0.6.2.2. `app/controllers/passkeys/sessions_controller.rb:22` calls `verify` only after it finds the credential ID in the database, so the attacker needs their own registered passkey.

### Step 4
- cose `key.rb` interpolates the decoded key type into its error message (read at the locked version).
- No code stringifies a saved-search Regexp.

### Step 5
- No constant pattern has both properties.
- The saved-search pattern is compiled case-insensitively, and its author can write a backreference. It is matched against post text.

### Step 6
- Rack defaults apply. No environment variable overrides them. Puma sets no `http_content_length_limit`.
- `app/jobs/import_job.rb:17` reads an uploaded file into one string and matches it. Uploads are limited to 50 MiB at `config/initializers/uploads.rb:3`, above the working line.
- No `ulimit`, `LimitAS` or `RLIMIT_AS` in the repository.

### Step 7
- The saved-search pattern is the only class 1 pattern. It is stored in a UTF-8 database at `app/models/saved_search.rb:20` and read back before `:31` compiles it, so it is UTF-8 by then.
- The other case-insensitive patterns are constants.

## Ask the deployment owner

- Address-space limit: run `cat /proc/1/limits` in a running web container and report the "Max address space" line. A value other than "unlimited" makes step 6 Exposed.
- Request body limit at the load balancer: what is the maximum body size, and does it apply to chunked requests? A limit under 1.33 GiB closes 2c at the edge.
- Memory for one web process: what limit applies? Under about 5.5 GiB, 2c ends in an out-of-memory failure instead of the bug.

## Not verified

- Other code paths that apply an affected method to fetched data. The entry point and the affected calls share one class, and only that class was traced. The probe was offered and not run.
- What Nokogiri does with the fetched body. It is outside the gems this review reads.
- The production image. The Dockerfile in the repository may not be the one deployed.
````
