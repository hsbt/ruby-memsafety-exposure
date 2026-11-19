# ruby-memsafety-exposure

An agent skill that reviews a Rails or Sinatra application for exposure to the Ruby memory-safety fixes in String case conversion and the regular expression engine ([advisory of 2026-11-18](https://www.ruby-lang.org/en/news/2026/11/18/multiple-vulnerabilities-in-regexp-and-string/)), and tells the maintainer what to do until Ruby is upgraded. Upgrading to Ruby 4.0.10, 3.4.13 or 3.3.14 is the fix. The review only reads code and never tries to trigger a bug.

## Single-file edition

[`dist/ruby-memsafety-exposure.md`](dist/ruby-memsafety-exposure.md) holds the whole procedure in one file. Open an agent session in the application's repository and paste it, or tell the agent to read it and follow it.

## Skill

Copy [`ruby-memsafety-exposure/`](ruby-memsafety-exposure/) into your agent's skills directory, such as `~/.claude/skills/`, and ask whether the application is affected. [`SKILL.md`](ruby-memsafety-exposure/SKILL.md) is the procedure, `references/` holds the material its steps point to, and `scripts/` has the checker and the AWS WAF generator for the proxy rule.

The skill is the source of the single file. After changing it, run `ruby build_single.rb > dist/ruby-memsafety-exposure.md`.

## Credits

The initializer that ignores the charset declared on multipart parts (action B) is from Ada Logics' report.
