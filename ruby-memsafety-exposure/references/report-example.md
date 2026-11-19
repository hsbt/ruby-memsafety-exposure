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
