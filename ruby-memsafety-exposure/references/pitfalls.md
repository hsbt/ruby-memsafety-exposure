# Checks and common misjudgments

## Checks before delivering

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

## Common misjudgments

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
