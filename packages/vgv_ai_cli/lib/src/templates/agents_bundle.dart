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
      "path": "{{#codex}}codex/{{#codex_hooks}}hooks/apply-patch-payload.sh{{/codex_hooks}}{{/codex}}",
      "data": "IyBSdW5zIGEgaG9vayBzY3JpcHQgd3JpdHRlbiBmb3IgQ2xhdWRlIENvZGUgYWdhaW5zdCBhIENvZGV4IHBheWxvYWQuCiMKIyBDb2RleCByZXBvcnRzIGEgZmlsZSBlZGl0IGFzIHRvb2xfbmFtZSAiYXBwbHlfcGF0Y2giIGFuZCBwdXRzIHRoZSB3aG9sZSBwYXRjaAojIGluIHRvb2xfaW5wdXQuY29tbWFuZCwgd2hlcmUgQ2xhdWRlIENvZGUgc2VuZHMgdGhlIG9uZSBmaWxlIGl0IGVkaXRlZCBpbgojIHRvb2xfaW5wdXQuZmlsZV9wYXRoLiBBIHNjcmlwdCB0aGF0IHJlYWRzIHRvb2xfaW5wdXQuZmlsZV9wYXRoIHRoZXJlZm9yZQojIGZpcmVzIGFuZCBmaW5kcyBub3RoaW5nLiBUaGlzIGZpbGxzIHRoZSBmaWVsZCBpbiBmcm9tIHRoZSBwYXRjaCBoZWFkZXJzIGFuZAojIHJ1bnMgdGhlIHNjcmlwdCBvbmNlIHBlciBmaWxlIHRoZSBwYXRjaCB0b3VjaGVzLgojCiMgVXNhZ2U6IGJhc2ggYXBwbHktcGF0Y2gtcGF5bG9hZC5zaCAnPHRoZSBjb21tYW5kIHRvIHJ1bj4nCiMKIyBXcml0dGVuIGJ5IGB2Z3ZfYWkgaW5zdGFsbGAuIEVkaXRzIGhlcmUgYXJlIG92ZXJ3cml0dGVuIG9uIHRoZSBuZXh0IHJ1bi4KCnNldCAtdW8gcGlwZWZhaWwKCndyYXBwZWQ9JDEKcGF5bG9hZD0kKGNhdCkKCnJ1bigpIHsKICBwcmludGYgJyVzJyAiJDEiIHwgc2ggLWMgIiR3cmFwcGVkIgp9CgojIFdpdGhvdXQganEgdGhlcmUgaXMgbm90aGluZyB0byB0cmFuc2xhdGUgd2l0aCwgc28gdGhlIHNjcmlwdCBnZXRzIHRoZSBwYXlsb2FkCiMgYXMgaXQgY2FtZS4gRXZlcnkgVkdWIGhvb2sgc2NyaXB0IGFscmVhZHkgc2tpcHMgaXRzZWxmIHdoZW4ganEgaXMgbWlzc2luZy4KaWYgISBjb21tYW5kIC12IGpxID4gL2Rldi9udWxsIDI+JjE7IHRoZW4KICBydW4gIiRwYXlsb2FkIgogIGV4aXQgJD8KZmkKCiMgVGhlIGZpbGVzIHRoaXMgcGF5bG9hZCBpcyBhYm91dDogdGhlIG9uZSBDbGF1ZGUgQ29kZSB3b3VsZCBoYXZlIG5hbWVkLCBwbHVzCiMgZXZlcnkgZmlsZSB0aGUgcGF0Y2ggaGVhZGVycyBuYW1lLiBBIGNoYXJhY3RlciBjbGFzcyBhdm9pZHMgYmFja3NsYXNoZXMsIHNvCiMgdGhlIHJlZ2V4IHN1cnZpdmVzIGJlaW5nIHJlbmRlcmVkIGZyb20gYSB0ZW1wbGF0ZS4KcGF0aHM9JChwcmludGYgJyVzJyAiJHBheWxvYWQiIHwganEgLXIgJ1soLnRvb2xfaW5wdXQuZmlsZV9wYXRoIC8vIGVtcHR5KSwgKCgudG9vbF9pbnB1dC5jb21tYW5kIC8vICIiKSB8IHNjYW4oIig/bSleWypdWypdWypdICg/OkFkZCBGaWxlfFVwZGF0ZSBGaWxlfE1vdmUgdG8pOiAoLispJCIpKV0gfCBmbGF0dGVuIHwgdW5pcXVlIHwgLltdJyAyPi9kZXYvbnVsbCkKCnN0YXR1cz0wCnJhbj0wCndoaWxlIElGUz0gcmVhZCAtciBwYXRoOyBkbwogICMgQSBkZWxldGVkIGZpbGUsIG9yIHRoZSBvbGQgbmFtZSBvZiBhIHJlbmFtZWQgb25lLCBpcyBubyBsb25nZXIgdGhlcmUgdG8KICAjIGFuYWx5emUgb3IgZm9ybWF0LCBzbyBpdCBkcm9wcyBvdXQgaGVyZSByYXRoZXIgdGhhbiBmYWlsaW5nIHRoZSBzY3JpcHQuCiAgaWYgWyAtbiAiJHBhdGgiIF0gJiYgWyAtZiAiJHBhdGgiIF07IHRoZW4KICAgIHJhbj0xCiAgICB0cmFuc2xhdGVkPSQocHJpbnRmICclcycgIiRwYXlsb2FkIiB8IGpxIC0tYXJnIHBhdGggIiRwYXRoIiAnLnRvb2xfaW5wdXQuZmlsZV9wYXRoID0gJHBhdGgnKQogICAgcnVuICIkdHJhbnNsYXRlZCIgfHwgc3RhdHVzPSQ/CiAgZmkKZG9uZSA8PEVPRgokcGF0aHMKRU9GCgojIE5vIHBheWxvYWQgZmllbGQgbmFtZWQgYSBmaWxlIHRoYXQgZXhpc3RzLCBzbyB0aGUgc2NyaXB0IGRlY2lkZXMgZm9yIGl0c2VsZi4KaWYgWyAiJHJhbiIgLWVxIDAgXTsgdGhlbgogIHJ1biAiJHBheWxvYWQiIHx8IHN0YXR1cz0kPwpmaQoKZXhpdCAkc3RhdHVzCg==",
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
  "version": "0.3.0+1",
  "environment": {"mason": "^0.1.0"},
  "publish_to": "none",
  "readme": {
    "path": "README.md",
    "data": "IyBhZ2VudHMKClRoZSBmaWxlcyBlYWNoIGNvZGluZyBhZ2VudCBoYXJuZXNzIHJlYWRzIHRvIHVzZSB0aGUgVkdWIHBsdWdpbnMuCgpgdmd2X2FpIGluc3RhbGxgIHJlbmRlcnMgdGhpcyBicmljayBpbnRvIG1lbW9yeSwgbmV2ZXIgaW50byB5b3VyIGhvbWUKZGlyZWN0b3J5LCBhbmQgaGFuZHMgZWFjaCBmaWxlIHRvIGl0cyByZWNvbmNpbGVyLiBTZXR0aW5ncyBmaWxlcyBhcmUgZGVlcAptZXJnZWQsIHNvIGtleXMgeW91IG93biBhcmUgcHJlc2VydmVkLgoKIyMgVGhlIHRyZWUgaXMgdGhlIGNhcGFiaWxpdHkgbWF0cml4CgpFYWNoIHRvcC1sZXZlbCBmb2xkZXIgaXMgb25lIGhhcm5lc3MgYW5kIGlzIHJlbmRlcmVkIG9ubHkgd2hlbiBpdHMgZmxhZyBpcyBzZXQuCldoYXQgYSBmb2xkZXIgY29udGFpbnMgaXMgd2hhdCB0aGF0IGhhcm5lc3Mgc3VwcG9ydHMuIFBpJ3MgZm9sZGVyIGhhcwpgQUdFTlRTLm1kYCBhbmQgYHByb21wdHMvYCBhbmQgbm90aGluZyBlbHNlLCBhbmQgdGhhdCBhYnNlbmNlIGlzIGhvdyBQaSBvcHRzCm91dCBvZiBhZ2VudHMgYW5kIHNldHRpbmdzLgoKfCBIYXJuZXNzICB8IFNldHRpbmdzICAgICAgICB8IGBBR0VOVFMubWRgIHwgQWdlbnRzICAgICAgICAgIHwgQ29tbWFuZHMgICAgICAgICAgIHwKfCAtLS0tLS0tLSB8IC0tLS0tLS0tLS0tLS0tLSB8IC0tLS0tLS0tLS0tIHwgLS0tLS0tLS0tLS0tLS0tIHwgLS0tLS0tLS0tLS0tLS0tLS0tIHwKfCBjbGF1ZGUgICB8IGBzZXR0aW5ncy5qc29uYCB8ICAgICAgICAgICAgIHwgICAgICAgICAgICAgICAgIHwgICAgICAgICAgICAgICAgICAgIHwKfCBnZW1pbmkgICB8IGBzZXR0aW5ncy5qc29uYCB8IHllcyAgICAgICAgIHwgYGFnZW50cy8qLm1kYCAgIHwgYGNvbW1hbmRzLyoudG9tbGAgIHwKfCBjb2RleCAgICB8IGBjb25maWcudG9tbGAgICB8IHllcyAgICAgICAgIHwgYGFnZW50cy8qLnRvbWxgIHwgICAgICAgICAgICAgICAgICAgIHwKfCBvcGVuY29kZSB8IGBvcGVuY29kZS5qc29uYCB8IHllcyAgICAgICAgIHwgYGFnZW50LyoubWRgICAgIHwgYGNvbW1hbmQvKi5tZGAgICAgIHwKfCBwaSAgICAgICB8ICAgICAgICAgICAgICAgICB8IHllcyAgICAgICAgIHwgICAgICAgICAgICAgICAgIHwgYHByb21wdHMvKi5tZGAgICAgIHwKCkNsYXVkZSBDb2RlIGluc3RhbGxzIHRoZSBwbHVnaW5zIG5hdGl2ZWx5IGZyb20gdGhlIG1hcmtldHBsYWNlLCBzbyBpdHMgZm9sZGVyCmhvbGRzIG9ubHkgdGhlIHNldHRpbmdzIHRoYXQgcG9pbnQgYXQgaXQuCgpUaGUgQ0xJIG1hcHMgZWFjaCBmb2xkZXIgb250byB0aGUgaGFybmVzcydzIGNvbmZpZyBkaXJlY3RvcnkuIEEgZmlsZSBhdCB0aGUKcm9vdCBvZiBhIGZvbGRlciBpcyBtZXJnZWQgaW50byB3aGF0IGlzIGFscmVhZHkgdGhlcmUuIEEgZmlsZSBpbiBhCnN1YmRpcmVjdG9yeSBiZWxvbmdzIHRvIFZHViBhbmQgaXMgd3JpdHRlbiB3aG9sZS4KCiMjIFBhcnRpYWxzCgpNYXJrZG93bi1zaGFwZWQgY29udGVudCBpcyBhIHBhcnRpYWwuIGB7e34gaW5zdHJ1Y3Rpb25zLm1kIH19YCBvcGVucyBldmVyeQpgQUdFTlRTLm1kYCBhbmQgaW5kZXhlcyB0aGUgc2tpbGxzLCBhbmQgYHt7fiBhZ2VudF9pbmRleC5tZCB9fWAgaW5kZXhlcyB0aGUKYWdlbnRzIGZvciB0aGUgaGFybmVzc2VzIHRoYXQgaGF2ZSB0aGVtLiBQaSBoYXMgbm8gc3ViYWdlbnRzLCBzbyBpdHMKYEFHRU5UUy5tZGAgbGVhdmVzIHRoZSBhZ2VudCBpbmRleCBvdXQuIGB7e34gYWdlbnQubWQgfX1gIGZyYW1lcyBhbiBhZ2VudAp1bmRlciBpdHMgZnJvbnRtYXR0ZXIuCgpEYXRhLXNoYXBlZCBjb250ZW50IGlzIHJlbmRlcmVkIGJ5IHRoZSBDTEkgYW5kIHBsYWNlZCB3aXRoIGEgdHJpcGxlIG11c3RhY2hlLgpNdXN0YWNoZSBjYW5ub3QgZXNjYXBlIFlBTUwsIFRPTUwgb3IgSlNPTiwgc28gZXZlcnkgc2V0dGluZ3MgZmlsZSwgZXZlcnkKZnJvbnRtYXR0ZXIgYmxvY2sgYW5kIGV2ZXJ5IFRPTUwgYWdlbnQgb3IgY29tbWFuZCBhcnJpdmVzIGZpbmlzaGVkLgoKIyMgVmFyaWFibGVzCgp8IFZhciAgICAgICAgICAgICAgICAgICAgICB8IFR5cGUgICAgfCBXaGF0IGl0IGlzICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHwKfCAtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0gfCAtLS0tLS0tIHwgLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLSB8CnwgYGNsYXVkZWAgLi4uIGBwaWAgICAgICAgIHwgYm9vbGVhbiB8IFdoaWNoIGhhcm5lc3NlcyB0byByZW5kZXIgICAgICAgICAgICAgICAgICAgICAgICAgIHwKfCBgPGhhcm5lc3M+X3NldHRpbmdzYCAgICAgfCBzdHJpbmcgIHwgVGhhdCBoYXJuZXNzJ3Mgc2V0dGluZ3MgZnJhZ21lbnQsIGFic2VudCBmb3IgUGkgICB8CnwgYGFnZW50c2AgICAgICAgICAgICAgICAgIHwgbGlzdCAgICB8IEVhY2ggYWdlbnQncyBgbmFtZWAsIGBpbnN0cnVjdGlvbnNgLCBhbmQgYSBtYXAgcGVyIGhhcm5lc3MgfAp8IGBjb21tYW5kc2AgICAgICAgICAgICAgICB8IGxpc3QgICAgfCBFYWNoIGludm9jYWJsZSBza2lsbCdzIGBuYW1lYCwgYGJvZHlgLCBhbmQgYSBtYXAgcGVyIGhhcm5lc3MgfAp8IGBpbmRleGAgICAgICAgICAgICAgICAgICB8IG1hcCAgICAgfCBgc2tpbGxzYCBhbmQgYGFnZW50c2AgdG8gbGlzdCBpbiBgQUdFTlRTLm1kYCAgICAgICAgfAoKYGFnZW50c2AgYW5kIGBjb21tYW5kc2AgYXJlIHRoZSBvbmx5IHRvcC1sZXZlbCBsaXN0cywgYW5kIHRoZSBDTEkgbGVhdmVzIGVpdGhlcgpvdXQgd2hlbiBpdCBpcyBlbXB0eS4gTWFzb24gcmVuZGVycyBhIHBhdGggbG9vcCBvbmNlIGZvciBldmVyeSBjb21iaW5hdGlvbiBvZgpldmVyeSB0b3AtbGV2ZWwgbGlzdCwgYW5kIHJlbmRlcnMgYW4gZW1wdHkgbGlzdCBhcyBhIGZpbGUgd2l0aCBubyBuYW1lLiBUaGUKYEFHRU5UUy5tZGAgbGlzdHMgbGl2ZSBpbnNpZGUgYGluZGV4YCBmb3IgdGhlIHNhbWUgcmVhc29uLgoKIyMgUmVnZW5lcmF0aW5nIHRoZSBidW5kbGUKClRoZSBidW5kbGUgaXMgY29tbWl0dGVkIGFuZCBDSSBmYWlscyBpZiBpdCBkcmlmdHM6CgpgYGBzaAp0b29sL2dlbmVyYXRlX2FnZW50c19idW5kbGUuc2gKYGBgCg==",
    "type": "text",
  },
  "changelog": {
    "path": "CHANGELOG.md",
    "data": "IyAwLjMuMCsxCgotIGZpeDogZHJvcCBgY29kZXgvcHJvbXB0cy9gLiBDb2RleCByZW1vdmVkIGN1c3RvbSBwcm9tcHRzIGluIDAuMTE3LjAsIHNvIHRoZQogIGZvbGRlciB3YXMgaW5lcnQsIGFuZCB0aGUgc2tpbGxzIGl0IGR1cGxpY2F0ZWQgYXJlIGFscmVhZHkgc2hhcmVkIHVuZGVyCiAgYH4vLmFnZW50cy9za2lsbHNgLgoKIyAwLjIuMCsxCgotIHJlZmFjdG9yOiBvd24gdGhlIHBlci1oYXJuZXNzIGxheW91dC4gQWdlbnRzLCBjb21tYW5kcyBhbmQgcHJvbXB0cyBhcmUKICByZW5kZXJlZCBpbnRvIGVhY2ggaGFybmVzcydzIG93biBkaXJlY3RvcmllcywgYW5kIGEgZGlyZWN0b3J5IGEgaGFybmVzcwogIGxhY2tzIGlzIHNpbXBseSBhYnNlbnQgZnJvbSBpdHMgdHJlZS4KLSByZWZhY3RvcjogdGFrZSBmaW5pc2hlZCBzZXR0aW5ncyBzdHJpbmdzIGZyb20gdGhlIENMSSBhbmQgZHJvcCB0aGUKICBgcHJlX2dlbmAgaG9vayBhbmQgaXRzIG1vZGVscy4KLSBmZWF0OiByZW5kZXIgYEFHRU5UUy5tZGAgZm9yIFBpLCB3aGljaCByZWFkcyBpdCBmcm9tIGB+Ly5waS9hZ2VudGAuIEl0CiAgaW5kZXhlcyB0aGUgc2tpbGxzIG9ubHksIHNpbmNlIFBpIGhhcyBubyBzdWJhZ2VudHMgdG8gZGVsZWdhdGUgdG8uCi0gZml4OiBkcm9wIGBwaS9zZXR0aW5ncy5qc29uYC4gUGkgcmVhZHMgYH4vLmFnZW50cy9za2lsbHNgIG5hdGl2ZWx5LCBzbyBpdHMKICBvbmx5IGVudHJ5IHdhcyByZWR1bmRhbnQuCgojIDAuMS4wKzEKCi0gZmVhdDogaW5pdGlhbCBicmljayBnZW5lcmF0aW5nIHN0YWdpbmcgb3V0cHV0IGZvciBDbGF1ZGUgQ29kZSwgR2VtaW5pIENMSSwKICBDb2RleCwgT3BlbkNvZGUgYW5kIFBpLgo=",
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
