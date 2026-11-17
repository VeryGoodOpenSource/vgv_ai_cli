// To generate this file, run: tool/generate_bundles.sh
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, implicit_dynamic_list_literal, implicit_dynamic_map_literal, inference_failure_on_collection_literal

import 'package:mason/mason.dart';

final projectConfigBundle = MasonBundle.fromJson(<String, dynamic>{
  "files": [
    {
      "path": "{{#claude}}claude/.claude/settings.json{{/claude}}",
      "data": "e3t7Y2xhdWRlX3NldHRpbmdzfX19",
      "type": "text",
    },
    {
      "path": "{{#codex}}codex/.codex/agents/{{#agents}}{{{name}}}.toml{{/agents}}{{/codex}}",
      "data": "e3sjYWdlbnRzfX17eyNjb2RleH19e3t7dG9tbH19fXt7L2NvZGV4fX17ey9hZ2VudHN9fQ==",
      "type": "text",
    },
    {
      "path": "{{#gemini}}gemini/.gemini/agents/{{#agents}}{{{name}}}.md{{/agents}}{{/gemini}}",
      "data": "e3sjYWdlbnRzfX17eyNnZW1pbml9fXt7PiBhZ2VudC5tZCB9fXt7L2dlbWluaX19e3svYWdlbnRzfX0=",
      "type": "text",
    },
    {
      "path": "{{#gemini}}gemini/.gemini/commands/{{#commands}}{{{name}}}.toml{{/commands}}{{/gemini}}",
      "data": "e3sjY29tbWFuZHN9fXt7I2dlbWluaX19e3t7dG9tbH19fXt7L2dlbWluaX19e3svY29tbWFuZHN9fQ==",
      "type": "text",
    },
    {
      "path": "{{#gemini}}gemini/.gemini/settings.json{{/gemini}}",
      "data": "eyJjb250ZXh0Ijp7ImZpbGVOYW1lIjpbIkFHRU5UUy5tZCIsIkdFTUlOSS5tZCJdfX0=",
      "type": "text",
    },
    {
      "path": "{{~ agent.md }}",
      "data": "e3t7ZnJvbnRtYXR0ZXJ9fX0Ke3t7aW5zdHJ1Y3Rpb25zfX19",
      "type": "text",
    },
  ],
  "hooks": [],
  "name": "project_config",
  "description": "The project-level files each coding agent harness reads to use the VGV plugins.",
  "version": "0.1.0+1",
  "environment": {"mason": "^0.1.0"},
  "publish_to": "none",
  "readme": {
    "path": "README.md",
    "data": "IyBwcm9qZWN0X2NvbmZpZwoKVGhlIHByb2plY3QtbGV2ZWwgZmlsZXMgZWFjaCBjb2RpbmcgYWdlbnQgaGFybmVzcyByZWFkcyB0byB1c2UgdGhlIFZHViBwbHVnaW5zLgoKYHZndl9haSBpbnN0YWxsIC0tcHJvamVjdGAgcmVuZGVycyB0aGlzIGJyaWNrIGludG8gbWVtb3J5IGFuZCBoYW5kcyBlYWNoIGZpbGUKdG8gaXRzIHJlY29uY2lsZXIsIHRoZSBzYW1lIHdheSBbYHVzZXJfY29uZmlnYF0oLi4vdXNlcl9jb25maWcvUkVBRE1FLm1kKSBpcwpyZW5kZXJlZCBmb3IgYSB1c2VyLWxldmVsIGluc3RhbGwuCgojIyBUaGUgdHJlZSBtaXJyb3JzIHRoZSByZXBvc2l0b3J5IHJvb3QKCkVhY2ggdG9wLWxldmVsIGZvbGRlciBpcyBvbmUgaGFybmVzcyBhbmQgaXMgcmVuZGVyZWQgb25seSB3aGVuIGl0cyBmbGFnIGlzIHNldC4KSW5zaWRlIGl0LCBmaWxlcyBzaXQgd2hlcmUgdGhhdCBoYXJuZXNzIHJlYWRzIHRoZW0gaW4gYSByZXBvc2l0b3J5LCBzdWNoIGFzCmB7eyNnZW1pbml9fWdlbWluaS8uZ2VtaW5pL2FnZW50cy/igKZgLiBBIGZpbGUgYXQgdGhlIHJvb3Qgb2YgdGhlIGZvbGRlciwgb3IKZGlyZWN0bHkgaW5zaWRlIG9uZSBvZiBpdHMgdG9wLWxldmVsIGZvbGRlcnMsIHN1Y2ggYXMgYC5jbGF1ZGUvc2V0dGluZ3MuanNvbmAsCmlzIG1lcmdlZCBpbnRvIHdoYXQgaXMgYWxyZWFkeSB0aGVyZS4gQW55dGhpbmcgZGVlcGVyIGJlbG9uZ3MgdG8gVkdWIGFuZCBpcwp3cml0dGVuIHdob2xlLgoKTm8gaGFybmVzcyBmb2xkZXIgaG9sZHMgYW4gaW5zdHJ1Y3Rpb25zIGZpbGU6IGEgcHJvamVjdCBpbnN0YWxsIG5ldmVyIHdyaXRlcwp0aGUgcmVwb3NpdG9yeSdzIGBBR0VOVFMubWRgLgoKfCBIYXJuZXNzIHwgU2V0dGluZ3MgICAgICAgICAgICAgICAgIHwgQWdlbnRzICAgICAgICAgICAgICAgICB8IENvbW1hbmRzICAgICAgICAgICAgICAgICAgfAp8IC0tLS0tLS0gfCAtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0gfCAtLS0tLS0tLS0tLS0tLS0tLS0tLS0tIHwgLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLSB8CnwgY2xhdWRlICB8IGAuY2xhdWRlL3NldHRpbmdzLmpzb25gICB8ICAgICAgICAgICAgICAgICAgICAgICAgfCAgICAgICAgICAgICAgICAgICAgICAgICAgIHwKfCBnZW1pbmkgIHwgYC5nZW1pbmkvc2V0dGluZ3MuanNvbmAgIHwgYC5nZW1pbmkvYWdlbnRzLyoubWRgICB8IGAuZ2VtaW5pL2NvbW1hbmRzLyoudG9tbGAgfAp8IGNvZGV4ICAgfCAgICAgICAgICAgICAgICAgICAgICAgICAgfCBgLmNvZGV4L2FnZW50cy8qLnRvbWxgIHwgICAgICAgICAgICAgICAgICAgICAgICAgICB8CgpUaGUgc2tpbGxzIGFyZSBub3QgaW4gdGhlIGJyaWNrLiBUaGUgQ0xJIHdyaXRlcyBvbmUgc2hhcmVkIGNvcHkgdG8KYC5hZ2VudHMvc2tpbGxzYCwgd2hpY2ggZXZlcnkgaGFybmVzcyBidXQgQ2xhdWRlIENvZGUgcmVhZHMgaW4gYSBwcm9qZWN0LCBhbmQKY29waWVzIHRoZSBwbHVnaW4gZmlsZXMgdGhvc2Ugc2tpbGxzIG5hbWUgdG8gYC52Z3ZfYWkvcGx1Z2lucy9gLgoKR2VtaW5pJ3Mgc2V0dGluZ3Mgb25seSBuYW1lIGBBR0VOVFMubWRgIGFuZCBgR0VNSU5JLm1kYCBhcyBjb250ZXh0IGZpbGVzLCBzbwpHZW1pbmkgcmVhZHMgdGhlIHJlcG9zaXRvcnkncyBvd24gYEFHRU5UUy5tZGAuIEl0cyBNQ1Agc2VydmVycyB3YWl0IGZvcgpwcm9qZWN0LWxldmVsIE1DUCBzdXBwb3J0LgoKIyMgUGFydGlhbHMKCmB7e34gYWdlbnQubWQgfX1gIGlzIGEgc3ltbGluayB0byB0aGUgYHVzZXJfY29uZmlnYCBwYXJ0aWFsLCBzbyBib3RoIGJyaWNrcwpmcmFtZSBhbiBhZ2VudCB0aGUgc2FtZSB3YXkgZnJvbSBvbmUgY29weS4gYG1hc29uIGJ1bmRsZWAgZm9sbG93cyBpdC4KCiMjIFZhcmlhYmxlcwoKVGhlIHNhbWUgYXMgYHVzZXJfY29uZmlnYCdzLiBTZWUgaXRzIFtSRUFETUVdKC4uL3VzZXJfY29uZmlnL1JFQURNRS5tZCN2YXJpYWJsZXMpLgoKIyMgUmVnZW5lcmF0aW5nIHRoZSBidW5kbGUKClRoZSBidW5kbGUgaXMgY29tbWl0dGVkIGFuZCBDSSBmYWlscyBpZiBpdCBkcmlmdHM6CgpgYGBzaAp0b29sL2dlbmVyYXRlX2J1bmRsZXMuc2gKYGBgCg==",
    "type": "text",
  },
  "vars": {
    "claude": {
      "type": "boolean",
      "description": "Configure Claude Code.",
      "default": true,
      "prompt": "Configure Claude Code?",
    },
    "gemini": {
      "type": "boolean",
      "description": "Configure Gemini CLI.",
      "default": true,
      "prompt": "Configure Gemini CLI?",
    },
    "codex": {
      "type": "boolean",
      "description": "Configure Codex.",
      "default": true,
      "prompt": "Configure Codex?",
    },
    "opencode": {
      "type": "boolean",
      "description": "Configure OpenCode.",
      "default": true,
      "prompt": "Configure OpenCode?",
    },
    "pi": {
      "type": "boolean",
      "description": "Configure Pi.",
      "default": true,
      "prompt": "Configure Pi?",
    },
    "copilot": {
      "type": "boolean",
      "description": "Configure Copilot CLI.",
      "default": true,
      "prompt": "Configure Copilot CLI?",
    },
    "antigravity": {
      "type": "boolean",
      "description": "Configure Antigravity CLI.",
      "default": true,
      "prompt": "Configure Antigravity CLI?",
    },
  },
});
