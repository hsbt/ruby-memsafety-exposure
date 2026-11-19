# Where to look inside the gems

Search for the symbol. File names differ between releases, and line numbers always do. Each fact below names the versions it was checked on. Confirm it in the locked version before relying on it.

## Getting the source

1. List the gem directories: `gem env` prints them under GEM PATHS. Search them with `find <dir> -maxdepth 2 -name '<gem>-*'`, not with shell globs.
2. `bundle show <gem>` is quicker when it works. It fails when the running Ruby differs from the one in the Gemfile, or when the version manager's configuration is not trusted.
3. If the locked version is not installed, look for `<gem>-<version>.gem` in the `cache` directory of a gem path and run `gem unpack` on it into a temporary directory. Otherwise `gem fetch <gem> -v <version>` and then `gem unpack`.
4. Say which version you read. If it is not the locked one, say so.

## Step 2a: request parameters

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

## Step 2b: who sets the encoding of fetched data

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

## Step 3 and 4: CBOR

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

## Step 7

Ruby compiles a regexp again in the encoding of the string it is matched against when the pattern is ASCII-only and the string has non-ASCII characters in an ASCII-compatible encoding (`rb_reg_prepare_enc` in `re.c`). Fixed ASCII-only case-insensitive patterns were matched against valid strings in Emacs-Mule and stateless-ISO-2022-JP on Ruby 4.0.9, about 13,000 combinations each, and none crashed. A pattern written in those encodings does.

## Step 5: dependencies with such patterns

First check that the gem loads in production: its Bundler group, `require: false`, and whether it is only a dependency of a development tool. If it does not, stop.

- haml: `find_and_preserve` (`helpers.rb` in 5.x, `preserver.rb` in 7.x). It runs only where a template uses `~` or calls `find_and_preserve`. An app that renders with hamlit does not use it.
- rouge: the lasso and php lexers.

Report them as Unknown with the reach of the text they process. Other dependencies are out of scope.

## Step 2c and 6: limits

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
