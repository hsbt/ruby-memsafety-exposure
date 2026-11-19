# WAF and proxy rule for step 2a

Use this when 2a is Exposed. It works alongside action B, and on its own until B ships. It covers request parameters only. It does nothing for steps 2b to 7.

## What to block

A multipart request in which a part without a filename declares `Content-Type: text/plain` with a `charset` other than UTF-8 or US-ASCII.

Write it as an allowlist. Rack accepts many spellings of the same header, and a rule that lists the charsets to block has to anticipate every one of them. A rule that lets two values through does not.

Two more rules of thumb:

- Match what Rack parses, not what browsers send. Charset names are case-insensitive, quotes are optional, whitespace around `=` and `;` is ignored, and from rack 3.1 a header line can be folded.
- A WAF inspects only the first part of a body. Reject multipart bodies larger than that limit on paths that do not take uploads, or the part can be placed beyond what the rule sees.

## The rule

`scripts/waf_rule.regex` is a regular expression for the request body, applied after lowercasing. It uses no lookahead, backreference or possessive quantifier, so it fits the restricted dialects WAFs accept.

Check it, or your own version of it, against Rack's real parser:

```bash
ruby -I <path to rack>/lib scripts/check_waf_rule.rb scripts/waf_rule.regex
```

The script builds thousands of part headers, asks Rack which encoding each one produces, and reports every header that Rack honours and the rule misses. It sends nothing and calls no case conversion. Expect "misses: 0" and "not matched: 0". Checked on rack 2.2.23, 3.0.18, 3.1.22 and 3.2.8.

It also prints what the rule does to ordinary requests. Two legitimate kinds match and will be blocked:

- Apache HttpClient 4 sends `charset=ISO-8859-1` on text parts by default.
- A multipart body that carries raw mail, such as an inbound mail webhook or an uploaded `.eml` file, when the mail has a text part in another charset.

Exclude the paths that receive these, or change those clients to send UTF-8.

## AWS WAF

```bash
ruby scripts/aws_wafv2_rules.rb 8192 > rules.json
```

This prints two rules for a web ACL: the regular expression on the body, and a block on multipart bodies above the inspection limit. Pass the limit of the protected resource: 8192 for an Application Load Balancer, and the configured value (16384 to 65536) for CloudFront, API Gateway and the others. Replace the placeholder path in the second rule with the paths that take uploads.

These rules were checked against Rack, not on a live web ACL. Deploy them in count mode first.

## Other products

Translate the condition above. If the product accepts PCRE-style expressions on the body, run the check script on your expression before deploying it.

## What to tell the user

In the report, action C names the product when the repository shows one (Terraform, CDN configuration) and states its body inspection limit if you know it. Mention the two kinds of legitimate request above only for an endpoint where the repository shows such a client or such content. Do not guess which endpoints they might hit.
