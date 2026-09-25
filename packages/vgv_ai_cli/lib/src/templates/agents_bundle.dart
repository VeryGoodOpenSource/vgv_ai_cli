// To generate this file, run: tool/generate_agents_bundle.sh
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, implicit_dynamic_list_literal, implicit_dynamic_map_literal, inference_failure_on_collection_literal

import 'package:mason/mason.dart';

final agentsBundle = MasonBundle.fromJson(<String, dynamic>{
  "files": [
    {
      "path": "{{#claude}}claude/settings.json{{/claude}}",
      "data": "e3t7Y2xhdWRlX3NldHRpbmdzfX19",
      "type": "text",
    },
    {
      "path": "{{#codex}}codex/agents/{{#agents}}{{{name}}}.toml{{/agents}}{{/codex}}",
      "data": "e3sjYWdlbnRzfX17eyNjb2RleH19e3t7dG9tbH19fXt7L2NvZGV4fX17ey9hZ2VudHN9fQ==",
      "type": "text",
    },
    {
      "path": "{{#codex}}codex/config.toml{{/codex}}",
      "data": "e3t7Y29kZXhfc2V0dGluZ3N9fX0=",
      "type": "text",
    },
    {
      "path": "{{#codex}}codex/prompts/{{#commands}}{{{name}}}.md{{/commands}}{{/codex}}",
      "data": "e3sjY29tbWFuZHN9fXt7e2JvZHl9fX17ey9jb21tYW5kc319",
      "type": "text",
    },
    {
      "path": "{{#gemini}}gemini/AGENTS.md{{/gemini}}",
      "data": "e3s+IGFnZW50cy5tZCB9fQ==",
      "type": "text",
    },
    {
      "path": "{{#gemini}}gemini/agents/{{#agents}}{{{name}}}.md{{/agents}}{{/gemini}}",
      "data": "e3sjYWdlbnRzfX17eyNnZW1pbml9fXt7PiBhZ2VudC5tZCB9fXt7L2dlbWluaX19e3svYWdlbnRzfX0=",
      "type": "text",
    },
    {
      "path": "{{#gemini}}gemini/commands/{{#commands}}{{{name}}}.toml{{/commands}}{{/gemini}}",
      "data": "e3sjY29tbWFuZHN9fXt7I2dlbWluaX19e3t7dG9tbH19fXt7L2dlbWluaX19e3svY29tbWFuZHN9fQ==",
      "type": "text",
    },
    {
      "path": "{{#gemini}}gemini/settings.json{{/gemini}}",
      "data": "e3t7Z2VtaW5pX3NldHRpbmdzfX19",
      "type": "text",
    },
    {
      "path": "{{#opencode}}opencode/agent/{{#agents}}{{{name}}}.md{{/agents}}{{/opencode}}",
      "data": "e3sjYWdlbnRzfX17eyNvcGVuY29kZX19e3s+IGFnZW50Lm1kIH19e3svb3BlbmNvZGV9fXt7L2FnZW50c319",
      "type": "text",
    },
    {
      "path": "{{#opencode}}opencode/AGENTS.md{{/opencode}}",
      "data": "e3s+IGFnZW50cy5tZCB9fQ==",
      "type": "text",
    },
    {
      "path": "{{#opencode}}opencode/command/{{#commands}}{{{name}}}.md{{/commands}}{{/opencode}}",
      "data": "e3sjY29tbWFuZHN9fXt7I29wZW5jb2RlfX17ez4gY29tbWFuZC5tZCB9fXt7L29wZW5jb2RlfX17ey9jb21tYW5kc319",
      "type": "text",
    },
    {
      "path": "{{#opencode}}opencode/opencode.json{{/opencode}}",
      "data": "e3t7b3BlbmNvZGVfc2V0dGluZ3N9fX0=",
      "type": "text",
    },
    {
      "path":
          "{{#pi}}pi/prompts/{{#commands}}{{{name}}}.md{{/commands}}{{/pi}}",
      "data": "e3sjY29tbWFuZHN9fXt7e2JvZHl9fX17ey9jb21tYW5kc319",
      "type": "text",
    },
    {
      "path": "{{#pi}}pi/settings.json{{/pi}}",
      "data": "e3t7cGlfc2V0dGluZ3N9fX0=",
      "type": "text",
    },
    {
      "path": "{{~ agent.md }}",
      "data": "e3t7ZnJvbnRtYXR0ZXJ9fX0Ke3t7aW5zdHJ1Y3Rpb25zfX19",
      "type": "text",
    },
    {
      "path": "{{~ agents.md }}",
      "data": "IyBBZ2VudCBpbnN0cnVjdGlvbnMKClRoZXNlIGluc3RydWN0aW9ucyBhcmUgbWFuYWdlZCBieSB0aGUgVkdWIEFJIENMSS4gVGhleSBtaXJyb3IgdGhlIHNraWxscyBhbmQKYWdlbnRzIHJlc29sdmVkIGZyb20gdGhlIGVuYWJsZWQgVkdWIHBsdWdpbnMgc28gZXZlcnkgaGFybmVzcyBzaGFyZXMgdGhlIHNhbWUKZ3VpZGFuY2UuCnt7I2luZGV4fX0KIyMgU2tpbGxzCgp7eyNoYXNfc2tpbGxzfX1Vc2UgYSBza2lsbCB3aGVuIGl0cyBkZXNjcmlwdGlvbiBtYXRjaGVzIHRoZSB0YXNrIGF0IGhhbmQuCgp7eyNza2lsbHN9fS0gKip7e3tuYW1lfX19Kio6IHt7e2Rlc2NyaXB0aW9ufX19Cnt7L3NraWxsc319e3svaGFzX3NraWxsc319e3teaGFzX3NraWxsc319Tm8gc2tpbGxzIGFyZSBjb25maWd1cmVkLgp7ey9oYXNfc2tpbGxzfX0KIyMgQWdlbnRzCgp7eyNoYXNfYWdlbnRzfX1EZWxlZ2F0ZSB0byBhbiBhZ2VudCB3aGVuIGl0cyBkZXNjcmlwdGlvbiBtYXRjaGVzIHRoZSB0YXNrIGF0IGhhbmQuCgp7eyNhZ2VudHN9fS0gKip7e3tuYW1lfX19Kio6IHt7e2Rlc2NyaXB0aW9ufX19Cnt7L2FnZW50c319e3svaGFzX2FnZW50c319e3teaGFzX2FnZW50c319Tm8gYWdlbnRzIGFyZSBjb25maWd1cmVkLgp7ey9oYXNfYWdlbnRzfX17ey9pbmRleH19",
      "type": "text",
    },
    {
      "path": "{{~ command.md }}",
      "data": "e3t7ZnJvbnRtYXR0ZXJ9fX0Ke3t7Ym9keX19fQ==",
      "type": "text",
    },
  ],
  "hooks": [],
  "name": "agents",
  "description":
      "The files each coding agent harness reads to use the VGV plugins.",
  "version": "0.2.0+1",
  "environment": {"mason": "^0.1.0"},
  "publish_to": "none",
  "readme": {
    "path": "README.md",
    "data": "IyBhZ2VudHMKClRoZSBmaWxlcyBlYWNoIGNvZGluZyBhZ2VudCBoYXJuZXNzIHJlYWRzIHRvIHVzZSB0aGUgVkdWIHBsdWdpbnMuCgpgdmd2X2FpIGluc3RhbGxgIHJlbmRlcnMgdGhpcyBicmljayBpbnRvIG1lbW9yeSwgbmV2ZXIgaW50byB5b3VyIGhvbWUKZGlyZWN0b3J5LCBhbmQgaGFuZHMgZWFjaCBmaWxlIHRvIGl0cyByZWNvbmNpbGVyLiBTZXR0aW5ncyBmaWxlcyBhcmUgZGVlcAptZXJnZWQsIHNvIGtleXMgeW91IG93biBhcmUgcHJlc2VydmVkLgoKIyMgVGhlIHRyZWUgaXMgdGhlIGNhcGFiaWxpdHkgbWF0cml4CgpFYWNoIHRvcC1sZXZlbCBmb2xkZXIgaXMgb25lIGhhcm5lc3MgYW5kIGlzIHJlbmRlcmVkIG9ubHkgd2hlbiBpdHMgZmxhZyBpcyBzZXQuCldoYXQgYSBmb2xkZXIgY29udGFpbnMgaXMgd2hhdCB0aGF0IGhhcm5lc3Mgc3VwcG9ydHMuIFBpJ3MgZm9sZGVyIGhhcwpgcHJvbXB0cy9gIGFuZCBub3RoaW5nIGVsc2UsIGFuZCB0aGF0IGFic2VuY2UgaXMgaG93IFBpIG9wdHMgb3V0IG9mIGFnZW50cy4KCnwgSGFybmVzcyAgfCBTZXR0aW5ncyAgICAgICAgfCBgQUdFTlRTLm1kYCB8IEFnZW50cyAgICAgICAgICB8IENvbW1hbmRzICAgICAgICAgICB8CnwgLS0tLS0tLS0gfCAtLS0tLS0tLS0tLS0tLS0gfCAtLS0tLS0tLS0tLSB8IC0tLS0tLS0tLS0tLS0tLSB8IC0tLS0tLS0tLS0tLS0tLS0tLSB8CnwgY2xhdWRlICAgfCBgc2V0dGluZ3MuanNvbmAgfCAgICAgICAgICAgICB8ICAgICAgICAgICAgICAgICB8ICAgICAgICAgICAgICAgICAgICB8CnwgZ2VtaW5pICAgfCBgc2V0dGluZ3MuanNvbmAgfCB5ZXMgICAgICAgICB8IGBhZ2VudHMvKi5tZGAgICB8IGBjb21tYW5kcy8qLnRvbWxgICB8CnwgY29kZXggICAgfCBgY29uZmlnLnRvbWxgICAgfCAgICAgICAgICAgICB8IGBhZ2VudHMvKi50b21sYCB8IGBwcm9tcHRzLyoubWRgICAgICB8Cnwgb3BlbmNvZGUgfCBgb3BlbmNvZGUuanNvbmAgfCB5ZXMgICAgICAgICB8IGBhZ2VudC8qLm1kYCAgICB8IGBjb21tYW5kLyoubWRgICAgICB8CnwgcGkgICAgICAgfCBgc2V0dGluZ3MuanNvbmAgfCAgICAgICAgICAgICB8ICAgICAgICAgICAgICAgICB8IGBwcm9tcHRzLyoubWRgICAgICB8CgpDbGF1ZGUgQ29kZSBpbnN0YWxscyB0aGUgcGx1Z2lucyBuYXRpdmVseSBmcm9tIHRoZSBtYXJrZXRwbGFjZSwgc28gaXRzIGZvbGRlcgpob2xkcyBvbmx5IHRoZSBzZXR0aW5ncyB0aGF0IHBvaW50IGF0IGl0LgoKVGhlIENMSSBtYXBzIGVhY2ggZm9sZGVyIG9udG8gdGhlIGhhcm5lc3MncyBjb25maWcgZGlyZWN0b3J5LiBBIGZpbGUgYXQgdGhlCnJvb3Qgb2YgYSBmb2xkZXIgaXMgbWVyZ2VkIGludG8gd2hhdCBpcyBhbHJlYWR5IHRoZXJlLiBBIGZpbGUgaW4gYQpzdWJkaXJlY3RvcnkgYmVsb25ncyB0byBWR1YgYW5kIGlzIHdyaXR0ZW4gd2hvbGUuCgojIyBQYXJ0aWFscwoKTWFya2Rvd24tc2hhcGVkIGNvbnRlbnQgaXMgYSBwYXJ0aWFsLiBge3t+IGFnZW50cy5tZCB9fWAgaXMgdGhlIHNoYXJlZAppbnN0cnVjdGlvbnMgaW5kZXgsIGFuZCBge3t+IGFnZW50Lm1kIH19YCBhbmQgYHt7fiBjb21tYW5kLm1kIH19YCBmcmFtZSBhbgphZ2VudCBvciBhIGNvbW1hbmQgdW5kZXIgaXRzIGZyb250bWF0dGVyLgoKRGF0YS1zaGFwZWQgY29udGVudCBpcyByZW5kZXJlZCBieSB0aGUgQ0xJIGFuZCBwbGFjZWQgd2l0aCBhIHRyaXBsZSBtdXN0YWNoZS4KTXVzdGFjaGUgY2Fubm90IGVzY2FwZSBZQU1MLCBUT01MIG9yIEpTT04sIHNvIGV2ZXJ5IHNldHRpbmdzIGZpbGUsIGV2ZXJ5CmZyb250bWF0dGVyIGJsb2NrIGFuZCBldmVyeSBUT01MIGFnZW50IG9yIGNvbW1hbmQgYXJyaXZlcyBmaW5pc2hlZC4KCiMjIFZhcmlhYmxlcwoKfCBWYXIgICAgICAgICAgICAgICAgICAgICAgfCBUeXBlICAgIHwgV2hhdCBpdCBpcyAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICB8CnwgLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tIHwgLS0tLS0tLSB8IC0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0gfAp8IGBjbGF1ZGVgIC4uLiBgcGlgICAgICAgICB8IGJvb2xlYW4gfCBXaGljaCBoYXJuZXNzZXMgdG8gcmVuZGVyICAgICAgICAgICAgICAgICAgICAgICAgICB8CnwgYDxoYXJuZXNzPl9zZXR0aW5nc2AgICAgIHwgc3RyaW5nICB8IFRoYXQgaGFybmVzcydzIHNldHRpbmdzIGZyYWdtZW50ICAgICAgICAgICAgICAgICAgIHwKfCBgYWdlbnRzYCAgICAgICAgICAgICAgICAgfCBsaXN0ICAgIHwgRWFjaCBhZ2VudCdzIGBuYW1lYCwgYGluc3RydWN0aW9uc2AsIGFuZCBhIG1hcCBwZXIgaGFybmVzcyB8CnwgYGNvbW1hbmRzYCAgICAgICAgICAgICAgIHwgbGlzdCAgICB8IEVhY2ggaW52b2NhYmxlIHNraWxsJ3MgYG5hbWVgLCBgYm9keWAsIGFuZCBhIG1hcCBwZXIgaGFybmVzcyB8CnwgYGluZGV4YCAgICAgICAgICAgICAgICAgIHwgbWFwICAgICB8IGBza2lsbHNgIGFuZCBgYWdlbnRzYCB0byBsaXN0IGluIGBBR0VOVFMubWRgICAgICAgICB8CgpgYWdlbnRzYCBhbmQgYGNvbW1hbmRzYCBhcmUgdGhlIG9ubHkgdG9wLWxldmVsIGxpc3RzLCBhbmQgdGhlIENMSSBsZWF2ZXMgZWl0aGVyCm91dCB3aGVuIGl0IGlzIGVtcHR5LiBNYXNvbiByZW5kZXJzIGEgcGF0aCBsb29wIG9uY2UgZm9yIGV2ZXJ5IGNvbWJpbmF0aW9uIG9mCmV2ZXJ5IHRvcC1sZXZlbCBsaXN0LCBhbmQgcmVuZGVycyBhbiBlbXB0eSBsaXN0IGFzIGEgZmlsZSB3aXRoIG5vIG5hbWUuIFRoZQpgQUdFTlRTLm1kYCBsaXN0cyBsaXZlIGluc2lkZSBgaW5kZXhgIGZvciB0aGUgc2FtZSByZWFzb24uCgojIyBSZWdlbmVyYXRpbmcgdGhlIGJ1bmRsZQoKVGhlIGJ1bmRsZSBpcyBjb21taXR0ZWQgYW5kIENJIGZhaWxzIGlmIGl0IGRyaWZ0czoKCmBgYHNoCnRvb2wvZ2VuZXJhdGVfYWdlbnRzX2J1bmRsZS5zaApgYGAK",
    "type": "text",
  },
  "changelog": {
    "path": "CHANGELOG.md",
    "data": "IyAwLjIuMCsxCgotIHJlZmFjdG9yOiBvd24gdGhlIHBlci1oYXJuZXNzIGxheW91dC4gQWdlbnRzLCBjb21tYW5kcyBhbmQgcHJvbXB0cyBhcmUKICByZW5kZXJlZCBpbnRvIGVhY2ggaGFybmVzcydzIG93biBkaXJlY3RvcmllcywgYW5kIGEgZGlyZWN0b3J5IGEgaGFybmVzcwogIGxhY2tzIGlzIHNpbXBseSBhYnNlbnQgZnJvbSBpdHMgdHJlZS4KLSByZWZhY3RvcjogdGFrZSBmaW5pc2hlZCBzZXR0aW5ncyBzdHJpbmdzIGZyb20gdGhlIENMSSBhbmQgZHJvcCB0aGUKICBgcHJlX2dlbmAgaG9vayBhbmQgaXRzIG1vZGVscy4KLSBmaXg6IGRyb3AgYGNvZGV4L0FHRU5UUy5tZGAsIHdoaWNoIENvZGV4IG5ldmVyIHJlYWRzLgoKIyAwLjEuMCsxCgotIGZlYXQ6IGluaXRpYWwgYnJpY2sgZ2VuZXJhdGluZyBzdGFnaW5nIG91dHB1dCBmb3IgQ2xhdWRlIENvZGUsIEdlbWluaSBDTEksCiAgQ29kZXgsIE9wZW5Db2RlIGFuZCBQaS4K",
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
  },
});
