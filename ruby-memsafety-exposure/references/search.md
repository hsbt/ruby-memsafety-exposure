# Search recipes

Starting points, not proofs. Each one over-matches, and none sees a construct that spans lines. Adjust the path list to the repository. A Sinatra app often keeps its code at the top level, so use `'*.rb'` there instead of `app lib config`. None uses `\b`, which `git grep -E` ignores on macOS.

## Step 2: affected case conversions

```bash
git grep -n -E '\.(upcase|swapcase)!?([^_a-zA-Z]|$)|casecmp\?|downcase!?\(:fold' -- app lib config
```

## Step 2a: method override in Sinatra

```bash
git grep -n -E "method_?override|Rack::MethodOverride|Sinatra::(Application|Base)|require ['\"]sinatra['\"]|Padrino" -- '*.rb' '*.ru'
```

A top-level `require "sinatra"` or a subclass of `Sinatra::Application` means the setting is on unless a `disable` follows.

## Step 2c: large data held in one string

Start from the inputs, because plain `downcase` and `capitalize` count here and they are everywhere:

```bash
git grep -n -E '\.(read|download|inflate)([^_a-zA-Z]|$)|Zlib::|Gzip|File\.(bin)?read|\.body\.to_s' -- app lib config
```

Then check whether an affected method, including plain `downcase` and `capitalize`, runs on what each returns.

## Step 2b: where an encoding is chosen

```bash
git grep -n -E 'Encoding\.find|String\.new\([^)]*encoding:|force_encoding|\.encode\(|response_body_encoding' -- app lib config
```

## Step 3: regexps that are not constants

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

## Step 5: case-insensitive patterns with a backreference

```bash
git grep -n -E '/[^/]*\\(k<|[1-9])[^/]*/[a-z]*i' -- app lib config
git grep -n -E 'IGNORECASE|\(\?[a-z]*i' -- app lib config
```

The first finds literals. The second finds patterns made case-insensitive in other ways. Read each hit for a backreference on the pattern side.
