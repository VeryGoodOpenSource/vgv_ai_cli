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
      "path": "{{#codex}}codex/AGENTS.md{{/codex}}",
      "data": "e3s+IGluc3RydWN0aW9ucy5tZCB9fXt7PiBhZ2VudF9pbmRleC5tZCB9fQ==",
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
      "path": "{{#codex}}codex/{{#codex_hooks}}hooks.json{{/codex_hooks}}{{/codex}}",
      "data": "e3t7Y29kZXhfaG9va3N9fX0=",
      "type": "text",
    },
    {
      "path": "{{#codex}}codex/{{#codex_hooks}}hooks/claude-payload.sh{{/codex_hooks}}{{/codex}}",
      "data": "IyBSdW5zIGEgaG9vayBzY3JpcHQgd3JpdHRlbiBmb3IgQ2xhdWRlIENvZGUgYWdhaW5zdCBhIENvZGV4IHBheWxvYWQuCiMKIyBNb3N0IG9mIHRoZSBwYXlsb2FkIGFscmVhZHkgbWF0Y2hlczogQ29kZXggc2VuZHMgdGhlIHNhbWUgc2Vzc2lvbl9pZCwgY3dkLAojIGhvb2tfZXZlbnRfbmFtZSwgdG9vbF9uYW1lIGFuZCB0b29sX2lucHV0LmNvbW1hbmQsIGFuZCBuYW1lcyBpdHMgc2hlbGwgdG9vbAojIEJhc2ggYW5kIGl0cyBNQ1AgdG9vbHMgbWNwX188c2VydmVyPl9fPHRvb2w+IGV4YWN0bHkgYXMgQ2xhdWRlIENvZGUgZG9lcy4KIyBBIGZpbGUgZWRpdCBpcyB3aGVyZSB0aGUgdHdvIHBhcnQgd2F5cy4gQ2xhdWRlIENvZGUgc2VuZHMgb25lIEVkaXQgb3IgV3JpdGUKIyBwZXIgZmlsZSwgbmFtaW5nIGl0IGluIHRvb2xfaW5wdXQuZmlsZV9wYXRoLiBDb2RleCBzZW5kcyBvbmUgYXBwbHlfcGF0Y2ggZm9yCiMgdGhlIHdob2xlIGNoYW5nZSwgd2l0aCB0aGUgcGF0Y2ggdGV4dCBpbiB0b29sX2lucHV0LmNvbW1hbmQgYW5kIG5vIGZpbGUgbmFtZWQKIyBhbnl3aGVyZSBhIHNjcmlwdCBjYW4gcmVhZCBpdC4KIwojIFNvIHRoaXMgdHJhbnNsYXRlcyB0aGF0IG9uZSBjYXNlOiBpdCByZWFkcyB0aGUgZmlsZXMgb3V0IG9mIHRoZSBwYXRjaAojIGhlYWRlcnMgYW5kIHJ1bnMgdGhlIHNjcmlwdCBvbmNlIHBlciBmaWxlLCBhcyB0aGUgRWRpdCBvciBXcml0ZSBDbGF1ZGUgQ29kZQojIHdvdWxkIGhhdmUgc2VudC4gRXZlcnkgb3RoZXIgcGF5bG9hZCBpcyBwYXNzZWQgdGhyb3VnaCBhcyBpdCBjYW1lLgojCiMgVXNhZ2U6IGJhc2ggY2xhdWRlLXBheWxvYWQuc2ggJzx0aGUgY29tbWFuZCB0byBydW4+JwojCiMgV3JpdHRlbiBieSBgdmd2X2FpIGluc3RhbGxgLiBFZGl0cyBoZXJlIGFyZSBvdmVyd3JpdHRlbiBvbiB0aGUgbmV4dCBydW4uCgpzZXQgLXVvIHBpcGVmYWlsCgp3cmFwcGVkPSQxCnBheWxvYWQ9JChjYXQpCgpydW4oKSB7CiAgcHJpbnRmICclcycgIiQxIiB8IHNoIC1jICIkd3JhcHBlZCIKfQoKIyBXaXRob3V0IGpxIHRoZXJlIGlzIG5vdGhpbmcgdG8gdHJhbnNsYXRlIHdpdGgsIHNvIHRoZSBzY3JpcHQgZ2V0cyB0aGUgcGF5bG9hZAojIGFzIGl0IGNhbWUuIEV2ZXJ5IFZHViBob29rIHNjcmlwdCBhbHJlYWR5IHNraXBzIGl0c2VsZiB3aGVuIGpxIGlzIG1pc3NpbmcuCmlmICEgY29tbWFuZCAtdiBqcSA+IC9kZXYvbnVsbCAyPiYxOyB0aGVuCiAgcnVuICIkcGF5bG9hZCIKICBleGl0ICQ/CmZpCgojIEVhY2ggZmlsZSB0aGlzIHBheWxvYWQgaXMgYWJvdXQsIGFzIHRoZSB0b29sIENsYXVkZSBDb2RlIHdvdWxkIGhhdmUgbmFtZWQKIyBmb3IgaXQ6IGFuIGFkZGVkIGZpbGUgaXMgYSBXcml0ZSwgYSBjaGFuZ2VkIG9yIHJlbmFtZWQgb25lIGFuIEVkaXQuIEEKIyBwYXlsb2FkIHRoYXQgYWxyZWFkeSBuYW1lcyBhIGZpbGUga2VlcHMgaXRzIG93biB0b29sIG5hbWUuCiMKIyBBIHBhdGNoIGhlYWRlciBuYW1lcyBhIGZpbGUgcmVsYXRpdmUgdG8gdGhlIHNlc3Npb24gcm9vdCB3aGVuIHRoZSBtb2RlbAojIHdyb3RlIGl0IHRoYXQgd2F5LCBzbyBlYWNoIHBhdGggaXMgcmVzb2x2ZWQgYWdhaW5zdCB0aGUgcGF5bG9hZCdzIG93biBjd2QKIyByYXRoZXIgdGhhbiB3aGVyZXZlciB0aGlzIHByb2Nlc3MgaGFwcGVucyB0byBiZSBydW5uaW5nLgojCiMgVGhlIHJlZ2V4ZXMgdXNlIGNoYXJhY3RlciBjbGFzc2VzIHNvIHRoaXMgaG9sZHMgbm8gYmFja3NsYXNoIGJlZm9yZSBhCiMgbmV3bGluZSwgd2hpY2ggbWFzb24gd291bGQgc3RyaXAgd2hlbiBpdCByZW5kZXJzIHRoZSBmaWxlLgplZGl0cz0kKHByaW50ZiAnJXMnICIkcGF5bG9hZCIgfCBqcSAtciAnCiAgLiBhcyAkcGF5bG9hZAogIHwgKCgkcGF5bG9hZC5jd2QgLy8gIi4iKSB8IHJ0cmltc3RyKCIvIikpIGFzICRjd2QKICB8IGRlZiBhYnNvbHV0ZTogaWYgc3RhcnRzd2l0aCgiLyIpIHRoZW4gLiBlbHNlICRjd2QgKyAiLyIgKyAuIGVuZDsKICAgIFsKICAgICAgKGlmICRwYXlsb2FkLnRvb2xfaW5wdXQuZmlsZV9wYXRoCiAgICAgICAgIHRoZW4gewogICAgICAgICAgIG5hbWU6ICRwYXlsb2FkLnRvb2xfbmFtZSwKICAgICAgICAgICBwYXRoOiAoJHBheWxvYWQudG9vbF9pbnB1dC5maWxlX3BhdGggfCBhYnNvbHV0ZSksCiAgICAgICAgIH0KICAgICAgICAgZWxzZSBlbXB0eSBlbmQpLAogICAgICAoKCRwYXlsb2FkLnRvb2xfaW5wdXQuY29tbWFuZCAvLyAiIikKICAgICAgICB8IHNjYW4oIig/bSleWypdWypdWypdIChBZGQgRmlsZXxVcGRhdGUgRmlsZXxNb3ZlIHRvKTogKC4rKSQiKQogICAgICAgIHwgewogICAgICAgICAgbmFtZTogKGlmIC5bMF0gPT0gIkFkZCBGaWxlIiB0aGVuICJXcml0ZSIgZWxzZSAiRWRpdCIgZW5kKSwKICAgICAgICAgIHBhdGg6ICguWzFdIHwgYWJzb2x1dGUpLAogICAgICAgIH0pCiAgICBdCiAgfCB1bmlxdWVfYnkoLnBhdGgpCiAgfCAuW10KICB8ICJcKC5uYW1lKVx0XCgucGF0aCkiCicgMj4vZGV2L251bGwpCgpzdGF0dXM9MApyYW49MAp3aGlsZSBJRlM9JCdcdCcgcmVhZCAtciBuYW1lIHBhdGg7IGRvCiAgIyBBIGRlbGV0ZWQgZmlsZSwgb3IgdGhlIG9sZCBuYW1lIG9mIGEgcmVuYW1lZCBvbmUsIGlzIG5vIGxvbmdlciB0aGVyZSB0bwogICMgYW5hbHl6ZSBvciBmb3JtYXQsIHNvIGl0IGRyb3BzIG91dCBoZXJlIHJhdGhlciB0aGFuIGZhaWxpbmcgdGhlIHNjcmlwdC4KICBpZiBbIC1uICIkcGF0aCIgXSAmJiBbIC1mICIkcGF0aCIgXTsgdGhlbgogICAgcmFuPTEKICAgIGVkaXQ9JChwcmludGYgJyVzJyAiJHBheWxvYWQiIHwganEgLS1hcmcgbmFtZSAiJG5hbWUiIC0tYXJnIHBhdGggIiRwYXRoIiAnLnRvb2xfbmFtZSA9ICRuYW1lIHwgLnRvb2xfaW5wdXQuZmlsZV9wYXRoID0gJHBhdGgnKQogICAgcnVuICIkZWRpdCIgfHwgc3RhdHVzPSQ/CiAgZmkKZG9uZSA8PDwgIiRlZGl0cyIKCiMgVGhpcyBwYXlsb2FkIGlzIGFib3V0IG5vIGZpbGUgdGhhdCBleGlzdHMsIHNvIGl0IG5lZWRzIG5vIHRyYW5zbGF0aW5nLgppZiBbICIkcmFuIiAtZXEgMCBdOyB0aGVuCiAgcnVuICIkcGF5bG9hZCIgfHwgc3RhdHVzPSQ/CmZpCgpleGl0ICRzdGF0dXMK",
      "type": "text",
    },
    {
      "path": "{{#gemini}}gemini/AGENTS.md{{/gemini}}",
      "data": "e3s+IGluc3RydWN0aW9ucy5tZCB9fXt7PiBhZ2VudF9pbmRleC5tZCB9fQ==",
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
      "data": "e3s+IGluc3RydWN0aW9ucy5tZCB9fXt7PiBhZ2VudF9pbmRleC5tZCB9fQ==",
      "type": "text",
    },
    {
      "path": "{{#opencode}}opencode/command/{{#commands}}{{{name}}}.md{{/commands}}{{/opencode}}",
      "data": "e3sjY29tbWFuZHN9fXt7I29wZW5jb2RlfX17e3tmcm9udG1hdHRlcn19fQp7e3tib2R5fX19e3svb3BlbmNvZGV9fXt7L2NvbW1hbmRzfX0=",
      "type": "text",
    },
    {
      "path": "{{#opencode}}opencode/opencode.json{{/opencode}}",
      "data": "e3t7b3BlbmNvZGVfc2V0dGluZ3N9fX0=",
      "type": "text",
    },
    {
      "path": "{{#pi}}pi/AGENTS.md{{/pi}}",
      "data": "e3s+IGluc3RydWN0aW9ucy5tZCB9fQ==",
      "type": "text",
    },
    {
      "path":
          "{{#pi}}pi/prompts/{{#commands}}{{{name}}}.md{{/commands}}{{/pi}}",
      "data": "e3sjY29tbWFuZHN9fXt7e2JvZHl9fX17ey9jb21tYW5kc319",
      "type": "text",
    },
    {
      "path": "{{~ agent.md }}",
      "data": "e3t7ZnJvbnRtYXR0ZXJ9fX0Ke3t7aW5zdHJ1Y3Rpb25zfX19",
      "type": "text",
    },
    {
      "path": "{{~ agent_index.md }}",
      "data": "e3sjaW5kZXh9fQojIyBBZ2VudHMKCnt7I2hhc19hZ2VudHN9fURlbGVnYXRlIHRvIGFuIGFnZW50IHdoZW4gaXRzIGRlc2NyaXB0aW9uIG1hdGNoZXMgdGhlIHRhc2sgYXQgaGFuZC4KCnt7I2FnZW50c319LSAqKnt7e25hbWV9fX0qKjoge3t7ZGVzY3JpcHRpb259fX0Ke3svYWdlbnRzfX17ey9oYXNfYWdlbnRzfX17e15oYXNfYWdlbnRzfX1ObyBhZ2VudHMgYXJlIGNvbmZpZ3VyZWQuCnt7L2hhc19hZ2VudHN9fXt7L2luZGV4fX0=",
      "type": "text",
    },
    {
      "path": "{{~ instructions.md }}",
      "data": "IyBBZ2VudCBpbnN0cnVjdGlvbnMKClRoZXNlIGluc3RydWN0aW9ucyBhcmUgbWFuYWdlZCBieSB0aGUgVkdWIEFJIENMSS4gVGhleSBtaXJyb3Igd2hhdCB0aGlzCmhhcm5lc3MgZ2V0cyBmcm9tIHRoZSBlbmFibGVkIFZHViBwbHVnaW5zLgp7eyNpbmRleH19CiMjIFNraWxscwoKe3sjaGFzX3NraWxsc319VXNlIGEgc2tpbGwgd2hlbiBpdHMgZGVzY3JpcHRpb24gbWF0Y2hlcyB0aGUgdGFzayBhdCBoYW5kLgoKe3sjc2tpbGxzfX0tICoqe3t7bmFtZX19fSoqOiB7e3tkZXNjcmlwdGlvbn19fQp7ey9za2lsbHN9fXt7L2hhc19za2lsbHN9fXt7Xmhhc19za2lsbHN9fU5vIHNraWxscyBhcmUgY29uZmlndXJlZC4Ke3svaGFzX3NraWxsc319e3svaW5kZXh9fQ==",
      "type": "text",
    },
  ],
  "hooks": [],
  "name": "agents",
  "description":
      "The files each coding agent harness reads to use the VGV plugins.",
  "version": "0.4.0+1",
  "environment": {"mason": "^0.1.0"},
  "publish_to": "none",
  "readme": {
    "path": "README.md",
    "data": "IyBhZ2VudHMKClRoZSBmaWxlcyBlYWNoIGNvZGluZyBhZ2VudCBoYXJuZXNzIHJlYWRzIHRvIHVzZSB0aGUgVkdWIHBsdWdpbnMuCgpgdmd2X2FpIGluc3RhbGxgIHJlbmRlcnMgdGhpcyBicmljayBpbnRvIG1lbW9yeSwgbmV2ZXIgaW50byB5b3VyIGhvbWUKZGlyZWN0b3J5LCBhbmQgaGFuZHMgZWFjaCBmaWxlIHRvIGl0cyByZWNvbmNpbGVyLiBTZXR0aW5ncyBmaWxlcyBhcmUgZGVlcAptZXJnZWQsIHNvIGtleXMgeW91IG93biBhcmUgcHJlc2VydmVkLgoKIyMgVGhlIHRyZWUgaXMgdGhlIGNhcGFiaWxpdHkgbWF0cml4CgpFYWNoIHRvcC1sZXZlbCBmb2xkZXIgaXMgb25lIGhhcm5lc3MgYW5kIGlzIHJlbmRlcmVkIG9ubHkgd2hlbiBpdHMgZmxhZyBpcyBzZXQuCldoYXQgYSBmb2xkZXIgY29udGFpbnMgaXMgd2hhdCB0aGF0IGhhcm5lc3Mgc3VwcG9ydHMuIFBpJ3MgZm9sZGVyIGhhcwpgQUdFTlRTLm1kYCBhbmQgYHByb21wdHMvYCBhbmQgbm90aGluZyBlbHNlLCBhbmQgdGhhdCBhYnNlbmNlIGlzIGhvdyBQaSBvcHRzCm91dCBvZiBhZ2VudHMgYW5kIHNldHRpbmdzLgoKfCBIYXJuZXNzICB8IFNldHRpbmdzICAgICAgICB8IGBBR0VOVFMubWRgIHwgQWdlbnRzICAgICAgICAgIHwgQ29tbWFuZHMgICAgICAgICAgIHwgSG9va3MgICAgICAgICB8CnwgLS0tLS0tLS0gfCAtLS0tLS0tLS0tLS0tLS0gfCAtLS0tLS0tLS0tLSB8IC0tLS0tLS0tLS0tLS0tLSB8IC0tLS0tLS0tLS0tLS0tLS0tLSB8IC0tLS0tLS0tLS0tLS0gfAp8IGNsYXVkZSAgIHwgYHNldHRpbmdzLmpzb25gIHwgICAgICAgICAgICAgfCAgICAgICAgICAgICAgICAgfCAgICAgICAgICAgICAgICAgICAgfCAgICAgICAgICAgICAgIHwKfCBnZW1pbmkgICB8IGBzZXR0aW5ncy5qc29uYCB8IHllcyAgICAgICAgIHwgYGFnZW50cy8qLm1kYCAgIHwgYGNvbW1hbmRzLyoudG9tbGAgIHwgICAgICAgICAgICAgICB8CnwgY29kZXggICAgfCBgY29uZmlnLnRvbWxgICAgfCB5ZXMgICAgICAgICB8IGBhZ2VudHMvKi50b21sYCB8ICAgICAgICAgICAgICAgICAgICB8IGBob29rcy5qc29uYCAgfAp8IG9wZW5jb2RlIHwgYG9wZW5jb2RlLmpzb25gIHwgeWVzICAgICAgICAgfCBgYWdlbnQvKi5tZGAgICAgfCBgY29tbWFuZC8qLm1kYCAgICAgfCAgICAgICAgICAgICAgIHwKfCBwaSAgICAgICB8ICAgICAgICAgICAgICAgICB8IHllcyAgICAgICAgIHwgICAgICAgICAgICAgICAgIHwgYHByb21wdHMvKi5tZGAgICAgIHwgICAgICAgICAgICAgICB8CgpDbGF1ZGUgQ29kZSBpbnN0YWxscyB0aGUgcGx1Z2lucyBuYXRpdmVseSBmcm9tIHRoZSBtYXJrZXRwbGFjZSwgc28gaXRzIGZvbGRlcgpob2xkcyBvbmx5IHRoZSBzZXR0aW5ncyB0aGF0IHBvaW50IGF0IGl0LgoKQ29kZXgncyBgaG9va3MuanNvbmAgY29tZXMgd2l0aCBgaG9va3MvY2xhdWRlLXBheWxvYWQuc2hgLCB3aGljaCBoYW5kcyBhCnBsdWdpbidzIGhvb2sgc2NyaXB0IHRoZSBDb2RleCBwYXlsb2FkIGluIHRoZSBzaGFwZSBDbGF1ZGUgQ29kZSBzZW5kcy4gQm90aAphcmUgcmVuZGVyZWQgb25seSB3aGVuIHRoZXJlIGFyZSBob29rcyBDb2RleCBjYW4gcnVuLgoKVGhlIENMSSBtYXBzIGVhY2ggZm9sZGVyIG9udG8gdGhlIGhhcm5lc3MncyBjb25maWcgZGlyZWN0b3J5LiBBIGZpbGUgYXQgdGhlCnJvb3Qgb2YgYSBmb2xkZXIgaXMgbWVyZ2VkIGludG8gd2hhdCBpcyBhbHJlYWR5IHRoZXJlLiBBIGZpbGUgaW4gYQpzdWJkaXJlY3RvcnkgYmVsb25ncyB0byBWR1YgYW5kIGlzIHdyaXR0ZW4gd2hvbGUuCgojIyBQYXJ0aWFscwoKTWFya2Rvd24tc2hhcGVkIGNvbnRlbnQgaXMgYSBwYXJ0aWFsLiBge3t+IGluc3RydWN0aW9ucy5tZCB9fWAgb3BlbnMgZXZlcnkKYEFHRU5UUy5tZGAgYW5kIGluZGV4ZXMgdGhlIHNraWxscywgYW5kIGB7e34gYWdlbnRfaW5kZXgubWQgfX1gIGluZGV4ZXMgdGhlCmFnZW50cyBmb3IgdGhlIGhhcm5lc3NlcyB0aGF0IGhhdmUgdGhlbS4gUGkgaGFzIG5vIHN1YmFnZW50cywgc28gaXRzCmBBR0VOVFMubWRgIGxlYXZlcyB0aGUgYWdlbnQgaW5kZXggb3V0LiBge3t+IGFnZW50Lm1kIH19YCBmcmFtZXMgYW4gYWdlbnQKdW5kZXIgaXRzIGZyb250bWF0dGVyLgoKRGF0YS1zaGFwZWQgY29udGVudCBpcyByZW5kZXJlZCBieSB0aGUgQ0xJIGFuZCBwbGFjZWQgd2l0aCBhIHRyaXBsZSBtdXN0YWNoZS4KTXVzdGFjaGUgY2Fubm90IGVzY2FwZSBZQU1MLCBUT01MIG9yIEpTT04sIHNvIGV2ZXJ5IHNldHRpbmdzIGZpbGUsIGV2ZXJ5CmZyb250bWF0dGVyIGJsb2NrIGFuZCBldmVyeSBUT01MIGFnZW50IG9yIGNvbW1hbmQgYXJyaXZlcyBmaW5pc2hlZC4KCiMjIFZhcmlhYmxlcwoKfCBWYXIgICAgICAgICAgICAgICAgICAgICAgfCBUeXBlICAgIHwgV2hhdCBpdCBpcyAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICB8CnwgLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tIHwgLS0tLS0tLSB8IC0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0gfAp8IGBjbGF1ZGVgIC4uLiBgcGlgICAgICAgICB8IGJvb2xlYW4gfCBXaGljaCBoYXJuZXNzZXMgdG8gcmVuZGVyICAgICAgICAgICAgICAgICAgICAgICAgICB8CnwgYDxoYXJuZXNzPl9zZXR0aW5nc2AgICAgIHwgc3RyaW5nICB8IFRoYXQgaGFybmVzcydzIHNldHRpbmdzIGZyYWdtZW50LCBhYnNlbnQgZm9yIFBpICAgfAp8IGBhZ2VudHNgICAgICAgICAgICAgICAgICB8IGxpc3QgICAgfCBFYWNoIGFnZW50J3MgYG5hbWVgLCBgaW5zdHJ1Y3Rpb25zYCwgYW5kIGEgbWFwIHBlciBoYXJuZXNzIHwKfCBgY29tbWFuZHNgICAgICAgICAgICAgICAgfCBsaXN0ICAgIHwgRWFjaCBpbnZvY2FibGUgc2tpbGwncyBgbmFtZWAsIGBib2R5YCwgYW5kIGEgbWFwIHBlciBoYXJuZXNzIHwKfCBgaW5kZXhgICAgICAgICAgICAgICAgICAgfCBtYXAgICAgIHwgYHNraWxsc2AgYW5kIGBhZ2VudHNgIHRvIGxpc3QgaW4gYEFHRU5UUy5tZGAgICAgICAgIHwKCmBhZ2VudHNgIGFuZCBgY29tbWFuZHNgIGFyZSB0aGUgb25seSB0b3AtbGV2ZWwgbGlzdHMsIGFuZCB0aGUgQ0xJIGxlYXZlcyBlaXRoZXIKb3V0IHdoZW4gaXQgaXMgZW1wdHkuIE1hc29uIHJlbmRlcnMgYSBwYXRoIGxvb3Agb25jZSBmb3IgZXZlcnkgY29tYmluYXRpb24gb2YKZXZlcnkgdG9wLWxldmVsIGxpc3QsIGFuZCByZW5kZXJzIGFuIGVtcHR5IGxpc3QgYXMgYSBmaWxlIHdpdGggbm8gbmFtZS4gVGhlCmBBR0VOVFMubWRgIGxpc3RzIGxpdmUgaW5zaWRlIGBpbmRleGAgZm9yIHRoZSBzYW1lIHJlYXNvbi4KCiMjIFJlZ2VuZXJhdGluZyB0aGUgYnVuZGxlCgpUaGUgYnVuZGxlIGlzIGNvbW1pdHRlZCBhbmQgQ0kgZmFpbHMgaWYgaXQgZHJpZnRzOgoKYGBgc2gKdG9vbC9nZW5lcmF0ZV9hZ2VudHNfYnVuZGxlLnNoCmBgYAo=",
    "type": "text",
  },
  "changelog": {
    "path": "CHANGELOG.md",
    "data": "IyAwLjQuMCsxCgotIGZlYXQ6IHJlbmRlciBgY29kZXgvaG9va3MuanNvbmAgYW5kIGBjb2RleC9ob29rcy9jbGF1ZGUtcGF5bG9hZC5zaGAsIHNvIHRoZQogIHBsdWdpbnMnIGhvb2tzIHJlYWNoIENvZGV4LiBCb3RoIGFyZSByZW5kZXJlZCBvbmx5IHdoZW4gdGhlIENMSSBzdXBwbGllcwogIGhvb2tzIGZvciBDb2RleCB0byBydW4uCgojIDAuMy4wKzEKCi0gZml4OiBkcm9wIGBjb2RleC9wcm9tcHRzL2AuIENvZGV4IHJlbW92ZWQgY3VzdG9tIHByb21wdHMgaW4gMC4xMTcuMCwgc28gdGhlCiAgZm9sZGVyIHdhcyBpbmVydCwgYW5kIHRoZSBza2lsbHMgaXQgZHVwbGljYXRlZCBhcmUgYWxyZWFkeSBzaGFyZWQgdW5kZXIKICBgfi8uYWdlbnRzL3NraWxsc2AuCgojIDAuMi4wKzEKCi0gcmVmYWN0b3I6IG93biB0aGUgcGVyLWhhcm5lc3MgbGF5b3V0LiBBZ2VudHMsIGNvbW1hbmRzIGFuZCBwcm9tcHRzIGFyZQogIHJlbmRlcmVkIGludG8gZWFjaCBoYXJuZXNzJ3Mgb3duIGRpcmVjdG9yaWVzLCBhbmQgYSBkaXJlY3RvcnkgYSBoYXJuZXNzCiAgbGFja3MgaXMgc2ltcGx5IGFic2VudCBmcm9tIGl0cyB0cmVlLgotIHJlZmFjdG9yOiB0YWtlIGZpbmlzaGVkIHNldHRpbmdzIHN0cmluZ3MgZnJvbSB0aGUgQ0xJIGFuZCBkcm9wIHRoZQogIGBwcmVfZ2VuYCBob29rIGFuZCBpdHMgbW9kZWxzLgotIGZlYXQ6IHJlbmRlciBgQUdFTlRTLm1kYCBmb3IgUGksIHdoaWNoIHJlYWRzIGl0IGZyb20gYH4vLnBpL2FnZW50YC4gSXQKICBpbmRleGVzIHRoZSBza2lsbHMgb25seSwgc2luY2UgUGkgaGFzIG5vIHN1YmFnZW50cyB0byBkZWxlZ2F0ZSB0by4KLSBmaXg6IGRyb3AgYHBpL3NldHRpbmdzLmpzb25gLiBQaSByZWFkcyBgfi8uYWdlbnRzL3NraWxsc2AgbmF0aXZlbHksIHNvIGl0cwogIG9ubHkgZW50cnkgd2FzIHJlZHVuZGFudC4KCiMgMC4xLjArMQoKLSBmZWF0OiBpbml0aWFsIGJyaWNrIGdlbmVyYXRpbmcgc3RhZ2luZyBvdXRwdXQgZm9yIENsYXVkZSBDb2RlLCBHZW1pbmkgQ0xJLAogIENvZGV4LCBPcGVuQ29kZSBhbmQgUGkuCg==",
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
