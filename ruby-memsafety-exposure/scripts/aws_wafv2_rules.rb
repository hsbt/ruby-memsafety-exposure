# Prints AWS WAF (WAFv2) rule JSON for the multipart charset mitigation.
#
#   ruby aws_wafv2_rules.rb [body-inspection-limit] > rules.json
#
# The body regex comes from waf_rule.regex, the same file check_waf_rule.rb verifies
# against Rack. The limit is 8192 for an Application Load Balancer and the
# configured value (16384 to 65536) for CloudFront and the other resources.
require "json"

regex = File.binread(File.join(__dir__, "waf_rule.regex")).chomp
limit = (ARGV[0] || 8192).to_i

visibility = ->(name) { { "SampledRequestsEnabled" => true, "CloudWatchMetricsEnabled" => true, "MetricName" => name } }
lowercase = [{ "Priority" => 0, "Type" => "LOWERCASE" }]
none = [{ "Priority" => 0, "Type" => "NONE" }]

rules = [
  {
    "Name" => "multipart-text-part-charset",
    "Priority" => 10,
    "Statement" => {
      "RegexMatchStatement" => {
        "RegexString" => regex,
        "FieldToMatch" => { "Body" => { "OversizeHandling" => "CONTINUE" } },
        "TextTransformations" => lowercase,
      },
    },
    "Action" => { "Block" => {} },
    "VisibilityConfig" => visibility.("multipart-text-part-charset"),
  },
  {
    "Name" => "multipart-body-over-inspection-limit",
    "Priority" => 11,
    "Statement" => {
      "AndStatement" => {
        "Statements" => [
          {
            "ByteMatchStatement" => {
              "SearchString" => "multipart/",
              "FieldToMatch" => { "SingleHeader" => { "Name" => "content-type" } },
              "TextTransformations" => lowercase,
              "PositionalConstraint" => "CONTAINS",
            },
          },
          {
            "SizeConstraintStatement" => {
              "FieldToMatch" => { "Body" => { "OversizeHandling" => "MATCH" } },
              "ComparisonOperator" => "GT",
              "Size" => limit,
              "TextTransformations" => none,
            },
          },
          {
            "NotStatement" => {
              "Statement" => {
                "ByteMatchStatement" => {
                  "SearchString" => "/REPLACE-WITH-AN-UPLOAD-PATH",
                  "FieldToMatch" => { "UriPath" => {} },
                  "TextTransformations" => none,
                  "PositionalConstraint" => "STARTS_WITH",
                },
              },
            },
          },
        ],
      },
    },
    "Action" => { "Block" => {} },
    "VisibilityConfig" => visibility.("multipart-body-over-inspection-limit"),
  },
]

puts JSON.pretty_generate(rules)
