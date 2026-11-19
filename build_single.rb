# Builds the single-file edition of the skill from the skill directory.
#
#   ruby build_single.rb > dist/ruby-memsafety-exposure.md
#
# The multi-file skill is the source. Every rewrite below aborts when its
# target text is gone, so the two editions cannot drift apart silently.
SKILL = File.join(__dir__, "ruby-memsafety-exposure")

SECTIONS = {
  "gem-checkpoints" => "Where to look inside the gems",
  "search" => "Search recipes",
  "mitigations" => "Actions",
  "waf" => "WAF and proxy rule for step 2a",
  "probe" => "Optional probe for step 2",
  "pitfalls" => "Checks and common misjudgments",
  "report-example" => "Example report",
}

def read(rel) = File.read(File.join(SKILL, rel))

def replace!(text, from, to)
  text.sub!(from, to) or abort "build_single: text not found: #{from.inspect[0, 70]}"
end

# Turns file references into section references.
def link_sections(text)
  text = text.gsub(/`references\/([a-z-]+)\.md`/) { %(the section "#{SECTIONS.fetch($1)}") }
  text = text.gsub("the reference file", %(the section "#{SECTIONS.fetch("gem-checkpoints")}"))
  text.gsub(/(?<=\. |^- |^)the section "/, 'The section "')
end

# Pushes every heading outside a code fence down by one level.
def demote(text)
  fenced = false
  text.lines.map { |line|
    fenced = !fenced if line.start_with?("```")
    !fenced && line.start_with?("#") ? "#" + line : line
  }.join
end

def reference(name)
  body = read("references/#{name}.md")
  replace!(body, /\A# .*\n/, "")
  "## Reference: #{SECTIONS.fetch(name)}\n" + demote(link_sections(body))
end

main = read("SKILL.md")
replace!(main, /\A---\n.*?\n---\n\n/m, "")
replace!(main,
  "This skill and the application under review are in different directories. Resolve `references/` against the directory this file is in, not against the working directory. Say which commit of the application you read.",
  "This file is the whole procedure. The sections named \"Reference\" at the end are material the steps point to. It lives outside the application under review. Say which commit of the application you read.")
replace!(main, "# Rails and Sinatra exposure review for the Ruby memory-safety fixes\n",
  "# Rails and Sinatra exposure review for the Ruby memory-safety fixes\n\n" \
  "> Single-file edition, generated from the multi-file skill. Paste it into an agent session opened in the application's repository, or tell the agent to read it and follow it.\n")

waf = read("references/waf.md")
replace!(waf, /\A# .*\n/, "")
regex = read("scripts/waf_rule.regex").chomp
replace!(waf,
  "`scripts/waf_rule.regex` is a regular expression for the request body, applied after lowercasing. It uses no lookahead, backreference or possessive quantifier, so it fits the restricted dialects WAFs accept.",
  "This is a regular expression for the request body, applied after lowercasing. It uses no lookahead, backreference or possessive quantifier, so it fits the restricted dialects WAFs accept.\n\n```text\n#{regex}\n```")
replace!(waf, /Check it, or your own version of it, against Rack's real parser:.*?Checked on rack 2\.2\.23, 3\.0\.18, 3\.1\.22 and 3\.2\.8\./m,
  "It was checked against Rack's real parser on rack 2.2.23, 3.0.18, 3.1.22 and 3.2.8: every part header that Rack honours matched. The check script ships with the multi-file skill.")
replace!(waf, "It also prints what the rule does to ordinary requests. Two legitimate kinds match and will be blocked:",
  "Two legitimate kinds of request match and will be blocked:")
replace!(waf, /```bash\nruby scripts\/aws_wafv2_rules\.rb 8192 > rules\.json\n```\n\nThis prints two rules for a web ACL: the regular expression on the body, and a block on multipart bodies above the inspection limit\. Pass the limit of the protected resource: 8192 for an Application Load Balancer, and the configured value \(16384 to 65536\) for CloudFront, API Gateway and the others\. Replace the placeholder path in the second rule with the paths that take uploads\./,
  "Use two rules in the web ACL. The first is a regex match on the body with the LOWERCASE text transformation and oversize handling CONTINUE. The second blocks multipart bodies above the inspection limit: a size constraint on the body with oversize handling MATCH, combined with a `content-type` header that contains `multipart/`, and excluding the paths that take uploads. The limit is 8192 for an Application Load Balancer, and the configured value (16384 to 65536) for CloudFront, API Gateway and the others. A generator for the rule JSON ships with the multi-file skill.")
replace!(waf, "run the check script on your expression before deploying it", "check your expression against Rack's parser before deploying it")

example = read("references/report-example.md")

out = +""
out << link_sections(main).rstrip << "\n\n"
out << reference("gem-checkpoints").rstrip << "\n\n"
out << reference("search").rstrip << "\n\n"
out << reference("mitigations").rstrip << "\n\n"
out << "## Reference: #{SECTIONS.fetch("waf")}\n" << demote(link_sections(waf)).rstrip << "\n\n"
out << reference("probe").rstrip << "\n\n"
out << reference("pitfalls").rstrip << "\n\n"
out << "## Reference: #{SECTIONS.fetch("report-example")}\n\n````markdown\n" << example.rstrip << "\n````\n"

abort "build_single: a file reference is left: #{$&}" if out =~ /references\/[a-z-]+\.md|scripts\/[a-z_]+\.(rb|regex)/
abort "build_single: unbalanced code fences" unless out.lines.count { |l| l.start_with?("```") && !l.start_with?("````") }.even?
print out
