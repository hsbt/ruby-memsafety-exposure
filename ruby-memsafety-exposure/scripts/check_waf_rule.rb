# Checks a WAF body regex against what Rack's multipart parser actually does.
#
#   ruby -I <rack>/lib check_waf_rule.rb waf_rule.regex [samples] [seed]
#
# For each generated part header it asks Rack which encoding the "_method"
# value ends up tagged with, and asks the regex (applied the way AWS WAF
# would, after the LOWERCASE text transformation) whether it matches the body.
# A header that Rack tags with one of the 14 encodings below and the regex
# does not match is a miss. Part values are harmless ASCII; nothing here
# calls a case-mapping method.
require "rack"
require "rack/mock_request" unless defined?(Rack::MockRequest)

TARGETS = %w[
  ISO-8859-1 ISO-8859-2 ISO-8859-3 ISO-8859-4 ISO-8859-9 ISO-8859-10
  ISO-8859-13 ISO-8859-14 ISO-8859-15 ISO-8859-16
  Windows-1250 Windows-1252 Windows-1254 Windows-1257
].map { |n| Encoding.find(n) }

# What a text part may be tagged with when the rule lets only UTF-8 and
# US-ASCII through. Rack falls back to binary for a name it does not know.
ALLOWED = [Encoding::UTF_8, Encoding::US_ASCII, Encoding::BINARY]

rule_src = File.binread(ARGV.fetch(0)).chomp
RULE = Regexp.new(rule_src.b, Regexp::NOENCODING)
SAMPLES = (ARGV[1] || 30_000).to_i
RNG = Random.new((ARGV[2] || 1).to_i)

def waf_view(body) = body.b.tr("A-Z", "a-z")

def body_for(head)
  "--B\r\nContent-Disposition: form-data; name=\"_method\"\r\n#{head}\r\n\r\nvalue\r\n--B--\r\n".b
end

# Returns the Encoding Rack gave the value, or a Symbol when there is none.
def rack_encoding(body, content_type = "multipart/form-data; boundary=B")
  env = Rack::MockRequest.env_for("/", method: "POST", input: body,
    "CONTENT_TYPE" => content_type, "CONTENT_LENGTH" => body.bytesize.to_s)
  value = Rack::Request.new(env).POST["_method"]
  value.is_a?(String) ? value.encoding : :no_value
rescue StandardError, EncodingError => e
  e.class.name.to_sym
end

names = (Encoding.name_list + %w[locale external internal filesystem] + ["", "x", "8859-1", "latin1", "l1"]).uniq

NAME_CASE = [:itself, :downcase, :upcase, :capitalize, :swapcase]
HEADER_NAMES = ["Content-Type", "content-type", "CONTENT-TYPE", "Content-type", "cOnTeNt-TyPe"]
AFTER_COLON = ["", " ", "  ", "\t", " \t ", "\r\n ", " \r\n\t", "\v", "\f", "\0"]
TYPES = ["text/plain", "Text/Plain", "TEXT/PLAIN", "text/plain ", "text/plain\t", "text/plain\0", "text/plain\v",
  "text/plain\r\n ", "text/html", "text/plain2", "application/octet-stream", ""]
SEPS = [";", " ; ", ";\t", ";\r\n ", "; x=y;", ";x=\"a;b\";", "; format=flowed; delsp=yes;", ";;", ";charset=utf-8;",
  "; charset=utf-8 ;", ";x;", ";=;", ";\0", ";\v", ";\f"]
KEYS = ["charset", "Charset", "CHARSET", " charset ", "\tcharset\t", "charset\0", "\0charset", "charset\v", "\vcharset",
  "charset\f", "charset\r\n ", "\r\n charset", "charset*", "xcharset", "charsetx", "char set"]
EQS = ["=", " = ", "=\t", "\t=", "= \r\n ", "\r\n\t=", "=\0", "\0=", "=\v", "=\f", "= \0 \v", "=="]
WRAPS = [%w[] * 2, ['"', '"'], ['"', ""], ["", '"'], ["'", "'"], ['" ', '"'], ['"', ' "'], [' "', '" '], ['""', '""']]
  .map { |a| a.size == 2 ? a : ["", ""] }
TAILS = ["", ";", " ", "; x=y", "\0", "\t", ";charset=utf-8", "; charset=US-ASCII", "\r\n ", "\v"]
EXTRA_LINES = ["", "X-A: b\r\n", "Content-Type: text/plain; charset=utf-8\r\n", "X-Content-Type: text/plain\r\n",
  "Content-Transfer-Encoding: 8bit\r\n"]

def build(rng, name)
  pick = ->(list) { list[rng.rand(list.size)] }
  w = pick.(WRAPS)
  line = pick.(HEADER_NAMES) + ":" + pick.(AFTER_COLON) + pick.(TYPES) + pick.(SEPS) + pick.(KEYS) + pick.(EQS) +
    w[0] + name.public_send(pick.(NAME_CASE)) + w[1] + pick.(TAILS)
  before = pick.(EXTRA_LINES)
  after = pick.(EXTRA_LINES)
  before + line + (after.empty? ? "" : "\r\n" + after.chomp)
end

stats = Hash.new(0)
misses = []
other_misses = []
other_tagged = Hash.new(0)
overblock = Hash.new(0)

check = lambda do |head, label|
  body = body_for(head)
  enc = rack_encoding(body)
  hit = RULE.match?(waf_view(body))
  target = TARGETS.include?(enc)
  stats[[target ? :target : :other, hit ? :match : :nomatch]] += 1
  misses << [label, head, enc] if target && !hit
  if enc.is_a?(Encoding) && !ALLOWED.include?(enc)
    other_tagged[enc.name] += 1
    other_misses << [label, head, enc] unless hit
  end
  overblock[enc.is_a?(Encoding) ? enc.name : enc] += 1 if !target && hit
  [enc, hit]
end

# 1. Every encoding name Ruby knows, in the plain form, in five spellings, bare and quoted.
names.each do |n|
  NAME_CASE.each do |c|
    v = n.public_send(c)
    check.("Content-Type: text/plain; charset=#{v}", "plain")
    check.("Content-Type: text/plain; charset=\"#{v}\"", "quoted")
  end
end
plain_stats = stats.dup

# 2. Random combinations of the syntax variations above.
SAMPLES.times do
  n = RNG.rand < 0.7 ? TARGETS[RNG.rand(TARGETS.size)].names[RNG.rand(2)] : names[RNG.rand(names.size)]
  check.(build(RNG, n), "random")
end

# 3. Requests that ordinary clients send. These should not match, except where noted.
benign = {
  "browser text field" => "--B\r\nContent-Disposition: form-data; name=\"_method\"\r\n\r\npatch\r\n--B--\r\n",
  "browser file, text/plain" => "--B\r\nContent-Disposition: form-data; name=\"f\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nhello\r\n--B--\r\n",
  "file with csv charset" => "--B\r\nContent-Disposition: form-data; name=\"f\"; filename=\"a.csv\"\r\nContent-Type: text/csv; charset=windows-1252\r\n\r\na,b\r\n--B--\r\n",
  "text part, charset=utf-8" => "--B\r\nContent-Disposition: form-data; name=\"a\"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nv\r\n--B--\r\n",
  "text part, charset=UTF-8 quoted" => "--B\r\nContent-Disposition: form-data; name=\"a\"\r\nContent-Type: text/plain; charset=\"UTF-8\"\r\n\r\nv\r\n--B--\r\n",
  "text part, charset=US-ASCII" => "--B\r\nContent-Disposition: form-data; name=\"a\"\r\nContent-Type: text/plain; charset=US-ASCII\r\n\r\nv\r\n--B--\r\n",
  "html meta in a field value" => "--B\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n<meta http-equiv=\"Content-Type\" content=\"text/html; charset=iso-8859-1\">\r\n--B--\r\n",
  "html meta charset in a file" => "--B\r\nContent-Disposition: form-data; name=\"f\"; filename=\"a.html\"\r\nContent-Type: text/html\r\n\r\n<meta charset=\"iso-8859-1\">\r\n--B--\r\n",
  "EXPECTED MATCH: Apache HttpClient 4 text part" => "--B\r\nContent-Disposition: form-data; name=\"a\"\r\nContent-Type: text/plain; charset=ISO-8859-1\r\nContent-Transfer-Encoding: 8bit\r\n\r\nv\r\n--B--\r\n",
  "EXPECTED MATCH: uploaded .eml with a latin-1 header" => "--B\r\nContent-Disposition: form-data; name=\"f\"; filename=\"a.eml\"\r\nContent-Type: message/rfc822\r\n\r\nSubject: x\r\nContent-Type: text/plain; charset=iso-8859-1\r\n\r\nhello\r\n--B--\r\n",
}

puts "rack #{Rack.release rescue Rack::RELEASE}, ruby #{RUBY_VERSION}, #{names.size} encoding names, #{SAMPLES} random samples"
puts "rule (#{rule_src.bytesize} bytes): #{rule_src}"
puts "plain forms:  #{plain_stats.sort.map { |k, v| "#{k.join("/")}=#{v}" }.join("  ")}"
puts "all forms:    #{stats.sort.map { |k, v| "#{k.join("/")}=#{v}" }.join("  ")}"
puts "misses (Rack tags a target encoding, rule does not match): #{misses.size}"
misses.first(15).each { |label, head, enc| puts "  #{label} #{enc} #{head.inspect}" }
puts "tagged with anything but UTF-8, US-ASCII or binary: #{other_tagged.values.sum} inputs, #{other_tagged.size} encodings, " \
  "not matched: #{other_misses.size} (#{other_misses.map { |_, _, e| e.name }.tally.sort_by { |_, v| -v }.first(8).map { |k, v| "#{k}=#{v}" }.join(" ")})"
other_misses.first(5).each { |label, head, enc| puts "  #{label} #{enc} #{head.inspect}" }
puts "matched although Rack did not tag a target encoding, by what Rack did:"
overblock.sort_by { |_, v| -v }.first(12).each { |k, v| puts "  #{v} #{k}" }
puts "ordinary requests:"
benign.each { |label, body| puts "  #{RULE.match?(waf_view(body)) ? "MATCH  " : "nomatch"} #{label}" }
