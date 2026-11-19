---
name: ruby-memsafety-exposure
description: Review a Rails or Sinatra application for exposure to the Ruby memory-safety fixes in String case conversion and the regular expression engine (the ruby-lang.org advisory of 2026-11-18, fixed in Ruby 4.0.10, 3.4.13 and 3.3.14), and tell the maintainer what to do until Ruby is upgraded. Use whenever someone asks whether their Rails or Sinatra app is affected by these Ruby security releases, wants an exposure audit of a Rails or Sinatra codebase, or needs to choose interim mitigations (gem updates, initializers, proxy or WAF rules) before they can upgrade Ruby. Read-only.
---

# Rails and Sinatra exposure review for the Ruby memory-safety fixes

Upgrading Ruby is the fix. This review answers two questions for one application: which affected surfaces an outsider can reach before the upgrade lands, and what the maintainer should do about each one. It reads code. It never tries to trigger a bug, and it contains nothing that would help someone do so.

## Two roots

This skill and the application under review are in different directories. Resolve `references/` against the directory this file is in, not against the working directory. Say which commit of the application you read.

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

- Read-only on the application. No file changes, no requests to the app or its deployments, no reproduction. Fetching public gem source is fine. In a working development setup you may run commands that only boot the app, such as `bin/rails middleware`. The probe in `references/probe.md` is the one exception to read-only, and only when the user asks for it.
- Judge the production configuration. Code that only runs in development or test is noted under Evidence and does not make a surface Exposed.
- Exposure is a conjunction. Each step names what must all be true. One false condition settles that surface, so check the cheapest condition first and stop there.
- Once a surface is Exposed at the lowest reach level, stop enumerating. Give up to three representative sites, and check that the action you will recommend closes them.
- A verdict rests on code you read. A control outside the repository (CDN, WAF, load balancer) can only lower a verdict. When every condition visible in the repository holds, the verdict is Exposed, and the outside control becomes a question. Use Unknown when the missing fact is one the verdict needs in order to be Exposed, such as the address-space limit in step 6. An example file (`*.example`, `*.sample`) shows a likely default, not the deployed value. Do not guess what is outside, and do not connect to a monitoring service, a cloud console or any other account to look it up, even when a connector for it is available. The person running the review may not have that access, and the review has to read the same for everyone. Write the exact command or question for the deployment owner instead.
- Name the framework. A Sinatra app mounted in a Rails app's routes runs behind the Rails middleware and then its own, so check both stacks.
- Gems to read at the locked version: rack; railties, actionpack and activesupport for Rails; sinatra, and padrino-core if locked, for Sinatra; cbor, webauthn, cose, the HTTP client the app uses, and a request sanitizer middleware if one is locked. `references/gem-checkpoints.md` says where to look, what is already known, and how to get the source. When a string leaves the app into any other gem, the verdict for that path is Not exposed, and the gem goes under "Not verified". When a string comes back from such a gem and reaches an affected method or a regexp, read just enough of the gem to learn the encoding of what it returns. If you cannot tell, the verdict is Unknown.
- `references/search.md` has search patterns for steps 2, 3 and 5, with a separate one for 2c.
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
- middleware order. Validation middleware below `Rack::MethodOverride` does not protect it. If a sanitizer middleware is locked, see the reference file: the common ones skip multipart bodies.
- whether code loaded at boot (a Rails initializer, or a file that `config.ru` or the Sinatra app requires) overrides the part charset handling, a proxy or WAF rule restricts it, or a proxy that ships in the repository rewrites multipart bodies before Rack sees them.
- other code that calls an affected method on a parameter. This matters only when `Rack::MethodOverride` is absent. In Sinatra routes and filters, count nested hash and array values only. Top-level values are UTF-8 there, through `params` and `request.POST` alike.

**2b. Strings whose encoding someone else chooses.** Exposed only if a string enters in an encoding its sender chose, is still in that encoding later, and an affected method runs on it. Entry points are HTTP responses, files, CSV, mail and anything passed to `force_encoding` or `Encoding.find`. `CSV.new(string, encoding: "UTF-8")` keeps the string's own encoding, so that option does not make a call safe. Parsers and stores that return UTF-8 end the trail (see the reference file). Background jobs that fetch from a third-party server are entry points with reach "No local account".

Work from the shorter list, because following every string has no end in a large codebase. List the entry points and the affected calls. If the calls are the shorter list, trace each receiver and argument back to where it came from. When every affected call is classified and none can receive a string in a sender-chosen encoding, 2b is Not exposed. If the entry points are the shorter list, start where the two lists share a file or a class, then follow each remaining entry point for two calls. If neither direction settles it, the verdict is Unknown and you offer the probe.

**2c. Very large strings, in any encoding.** The length of the converted string is counted in 32 bits, so once the output passes 4 GiB the result is written past its buffer. Exposed only if a string from outside, with at least one non-ASCII character, can reach one of these methods at the size shown, and no layer in the repository stops it first. UTF-8 counts here. A string that is ASCII only takes another path.

| Methods, with their bang forms | Smallest input that can trigger it |
|---|---|
| `upcase`, `swapcase`, `downcase(:fold)`, `casecmp?` (either operand) | 1.33 GiB in UTF-8, UTF-16 or UTF-32. 2 GiB in the single-byte encodings of 2a |
| `downcase`, `capitalize` | 2 GiB in UTF-16 or UTF-32. 2.67 GiB in UTF-8 |

Check:

- `Rack::MethodOverride`. It takes `_method` from URL-encoded and multipart bodies. Whether `_method` can reach the size above depends on the locked rack and on its environment variables (see the reference file). Where it can, an unauthenticated POST reaches `upcase`.
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

For dependencies, check only the ones in the reference file, and only if they load in production.

### 6. Size limits

The allocation that can fail grows with the length of the string, so there is no exact size. Use 1 MiB as the working line.

Count matches in the application's own code. A match inside a gem is out of scope.

- Not exposed: nothing in the repository lets an untrusted string above that line reach a regexp match.
- Exposed: such a string can reach a match, and the process runs under an address-space limit (`RLIMIT_AS`, `ulimit -v`, systemd `LimitAS`). A limit makes this worse, not better. It is what lets the allocation fail.
- Unknown: such a string can reach a match, and no address-space limit is visible. Ask the owner, for each kind of process that runs the match (web, job workers). A cgroup memory limit or an RSS watchdog is a different mechanism. Report it, and leave the verdict Unknown.

To find the largest string, answer per layer: proxy, CDN or WAF (Unknown unless configured in the repository), a WAF that runs inside the app, a proxy that ships in the repository in any language, the app server, Rack, the application. For each, say whether the limit counts bytes received or trusts `Content-Length`. Body parameters are parsed for any HTTP method, so a route that only answers GET still receives them. Defaults are in the reference file. Then look for code that holds a whole body or file in one string and matches it: middleware that scans bodies, mail bodies, parsed uploads, repository blobs, CI logs, fetched documents.

### 7. Regexps in another encoding

Exposed only if a class 1 pattern from step 3 is matched case-insensitively, and the pattern itself can reach the compiler in an encoding its sender chose. That needs the pattern to come straight from a string found in 2a or 2b. A pattern that is stored and read back from a UTF-8 database, or that arrives as JSON or as a URL-encoded parameter, is UTF-8 by then.

A pattern the application wrote does not count, even though Ruby compiles an ASCII pattern again in the encoding of the string it is matched against. Fixed ASCII patterns were tested against strings in such encodings and did not trigger the bug (see the reference file). The same holds for a class 3 pattern, unless the admin can supply it in another encoding.

The actions that close 2a and 2b close this step for the same strings.

## Report

Before writing, read `references/pitfalls.md` and run its checks against your findings. `references/report-example.md` shows a finished report.

Put one line under the title: `Action needed: Yes`, `No` or `Unknown`. It is No when step 1 is Fixed. Otherwise it follows the worst verdict among the other steps: Yes for Exposed, Unknown for Unknown, No when every one is Not exposed.

Lead with what to do. A maintainer who reads only the first section should know their next three actions. Pick actions from `references/mitigations.md`, name the step each one closes, and order them by reach level.

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
