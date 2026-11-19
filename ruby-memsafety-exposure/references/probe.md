# Optional probe for step 2

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
