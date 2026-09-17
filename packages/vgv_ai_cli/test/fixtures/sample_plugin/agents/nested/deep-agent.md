---
name: deep-agent
description: |
  A nested agent whose description is a literal scalar carrying XML.

  <examples>
    <example>
      user: "review this"
      assistant: "I'll use the deep agent."
    </example>
  </examples>
skills:
  - elements-of-style
  - testing
model: sonnet
effort: medium
category: review
---

# Deep agent

Nested one level under `agents/`, the way `vgv-wingspan` ships its agents.

---

A section following a markdown rule. The rule above is a line that is exactly
three dashes, which is what breaks a naive frontmatter splitter.

---

A second section, after a second rule, so the test proves the splitter stops at
the first closing fence rather than the last.
