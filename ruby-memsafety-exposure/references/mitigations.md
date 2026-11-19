# Actions

Every report starts with A. The others are interim measures. Each one closes an entry point, not the bug, so none of them replaces the upgrade.

| Action | Use when | Closes |
|---|---|---|
| A. Upgrade Ruby | Always | Everything |
| B. Ignore the charset declared on multipart parts | 2a is Exposed | 2a, and 7 for patterns that arrive as parameters |
| C. Reject multipart text parts that declare a charset other than UTF-8 or US-ASCII, at the proxy or WAF. `references/waf.md` has the rule and how to check it | 2a is Exposed. Use it with B, or alone until B ships | 2a, within the body size the edge inspects |
| D. Stop CBOR from building regexps: update cbor to 0.6.2.2 or later, or add the initializer | The locked cbor is older than 0.6.2.2 and untrusted CBOR is decoded | The CBOR part of 3 and 4 |
| E. Cap request bodies by bytes received, and cap input length before case conversion or matching | 2c or 6 is Exposed or Unknown | 2c and 6 |
| F. Rewrite the regexp: drop the case-insensitive flag or the backreference | 5 is Exposed for a pattern the app owns | 5 |
| G. Convert to UTF-8, or reject, where the data enters | 2b is Exposed | 2b, and 7 for the same data |
| H. Restrict who can write patterns, cap pattern length, or compile user patterns with another engine such as RE2. Remove Regexp from the classes YAML may load | 3 reports class 1 or 3 | Another engine closes 3, 4, 5 and 7 for the patterns moved to it. The rest only narrows them |
| I. Update rack to 2.2.19, 3.1.17, 3.2.2 or later, and leave `RACK_MULTIPART_BUFFERED_UPLOAD_BYTESIZE_LIMIT` and `RACK_QUERY_PARSER_BYTESIZE_LIMIT` at their defaults. The 3.0 line has no such release, so move to 3.1 or later | 2c is Exposed through `Rack::MethodOverride` or another URL-encoded or multipart parameter | 2c for those parameters. JSON parameters need E |
| J. Turn method override off where nothing sends `_method`: `disable :method_override` in a Sinatra app, or remove `use Rack::MethodOverride` from `config.ru`. Search the views and JavaScript for `_method` first. Rails form helpers send it, so this rarely fits a Rails app | 2a or 2c is Exposed through `Rack::MethodOverride` | 2a and 2c for `_method`. Other parameters still need B, C or I |

C is a second layer, not a replacement for B. A WAF inspects only the first part of a body and blocks some legitimate clients, and B has neither problem.

B and C do not close 2c. They stop the declared charset, and 2c needs none.

## B. Ignore the charset declared on multipart parts

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

## D. Stop CBOR from building regexps

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
