# 0.4.0+1

- fix: namespace Gemini commands under `commands/vgv/`, so they load as
  `/vgv:plan`, `/vgv:build` and so on. Gemini CLI renames any custom command
  whose name matches a built-in, and `/plan` already does.

