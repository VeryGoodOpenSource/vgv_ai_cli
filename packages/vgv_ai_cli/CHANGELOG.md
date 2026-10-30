# Changelog

## [0.1.0](https://github.com/VeryGoodOpenSource/vgv_ai_cli/compare/v0.1.0...v0.1.0) (2026-10-29)


### Features

* add agents brick and bundle ([#7](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/7)) ([f17a369](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/f17a36914c4802d3621007d04d0fb3920a3ca095))
* add the install manifest contract ([#40](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/40)) ([6e0b99e](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/6e0b99eec3a5cb20b4a8f5d2380312e595cf12b7))
* add vgv_ai doctor ([#56](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/56)) ([c56d187](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/c56d187c081c199ea8464c308e556da2b0273b18))
* add vgv_ai uninstall ([#61](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/61)) ([e9d11ed](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/e9d11edefbd555c32039da0640f4a30509b29a38))
* **antigravity:** add Antigravity CLI as a harness ([#65](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/65)) ([6b0a882](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/6b0a882ac57af643b2d6d21e83a4ed0653953a7b))
* bump very_good_workflows@v2 ([#92](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/92)) ([aa2cd46](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/aa2cd46bf3ba2e9f5d3737818cec595d4401ff25))
* choose which VGV plugins each harness is installed from ([#97](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/97)) ([a3e0099](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/a3e00993e8bd6d4d69cab5641864c1574f1029f2))
* **cli:** add install command ([#33](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/33)) ([945ff79](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/945ff79aefa9673bb65e0e78f2f3cf9c19b3c917))
* **cli:** add the install reconcile layer ([#32](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/32)) ([8e39a88](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/8e39a8855106484c460e02e88bf01e0c63bce39a))
* **codex:** translate the plugins' hooks into Codex ([#51](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/51)) ([9306b5f](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/9306b5fe63d351fab82515fb7c2ab112d5d8c5cf))
* **copilot:** add GitHub Copilot CLI as a harness ([#59](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/59)) ([a904b93](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/a904b93857c8dd43cc91e54978b95d4681043b9a))
* **copilot:** translate the plugins' hooks into Copilot ([#63](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/63)) ([179f1d5](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/179f1d5fd92e5c9a5b52e93e4217cfa0000249f0))
* detect installed harnesses ([#26](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/26)) ([33392df](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/33392dff3b206578defcf5692340dd5677e48a97))
* **install:** resolve plugins over git when claude cache is missing ([#55](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/55)) ([6ce8f6d](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/6ce8f6d350b28d209b7c676a1b1db0cc7096b5c8))
* **reconcile:** scope MD and TOML edits to managed content ([#39](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/39)) ([c43f719](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/c43f71913b02d19c18f327845ce7c3cace1e9d36))
* resolve and parse the VGV plugins ([#27](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/27)) ([7b74b6f](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/7b74b6fdb5bca04f970553d31e90ca07b5c0d500))


### Bug Fixes

* **codex:** stop writing ~/.codex/prompts ([#50](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/50)) ([c8b5ac2](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/c8b5ac2e9a8c6ac100f42048cab51b164643a554))
* pin packages to 0.1.0 ([#106](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/106)) ([93e73be](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/93e73bea32a70798273caa42edf1ff45ef68ed4f))
* quieten the update check and say how to recover a newer manifest ([#99](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/99)) ([687ec08](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/687ec08e50944373118ea02911c2b9d0395ab945))
* treat MCP argv lists as single values on install ([#82](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/82)) ([137904e](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/137904eac32cc066ca34d9ab5e869507ba13ecf5))


### Refactors

* **plugin_source:** harness-neutral parsing ([#30](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/30)) ([30e2e93](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/30e2e9368fba4d553d56acf8c001bffb5836a2e7))
* run cognitive complexity ([#52](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/52)) ([c293c3c](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/c293c3ca649e13e55322869b262552d8d6647e1e))
* **structure:** flatten harness/ into detect/ and translate/ ([#43](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/43)) ([0f89523](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/0f895237d5f1dff83569aa6ccadd98c85b101d97))
* **translate:** move harness layout to agents brick ([#37](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/37)) ([556cedb](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/556cedb1d8030c36f42715c9316b2648f2bd6eb5))
* **translate:** move harness translators into translators/ ([#87](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/87)) ([60de9f0](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/60de9f0932174e9f58cd887d8a3e223244b3d8bd))
* **translate:** replace maps with typed translate models ([#42](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/42)) ([e755f1c](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/e755f1cf2bc233c433c3954d1f06bfea5f37b510))
* use primary constructors ([#66](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/66)) ([092047f](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/092047fb0022c898f1167d461357d8cfd1938fd4))
* validate files with ack schemas ([#77](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/77)) ([2a78fbb](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/2a78fbbc06b4ba1a71fdf4b3746339886cec32bd))


### Miscellaneous Chores

* add cli package ([#1](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/1)) ([9076c90](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/9076c908ce8b5cced9fdfe91992e294a00868a2f))
* add shared agent config and adopt AGENTS.md convention ([#5](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/5)) ([42e35d3](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/42e35d39f6f9e3eeba43ed5c547168b073443a00))
* adopt Very Good CLI release and repo conventions ([#100](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/100)) ([832d3d9](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/832d3d91eb381d736a0a182604d3a3eb9a676ba9))
* initial commit ([4d5feeb](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/4d5feebadd5ed8f267fb6861a03e0dfef99fb613))
* remove sample command ([#57](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/57)) ([d9e8675](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/d9e8675cea795c2838af26b48ebea2d6798660de))
* reset versions for publishing ([#84](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/84)) ([cdef94d](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/cdef94d7e07428017338c114b461f409813c47ac))
* run very_good_analysis with no rule overrides ([#102](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/102)) ([c93ea52](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/c93ea528e7bac17fc4dae928719f7828ce181f4d))
* update dependencies and pins ahead of release ([#85](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/85)) ([6a6cb7f](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/6a6cb7ff51bd36e1d7f69d30e2d83917a3db2e20))
* **vgv_ai_cli:** clean up docs and code ([#88](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/88)) ([1beec5f](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/1beec5fef8ee43599d2cc43f215ee38e1cd53c60))


### Docs

* document shell completion, Windows support and the new conventions ([#101](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/101)) ([58c7e0d](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/58c7e0dca2c0f625793dd5b121609de7dae483bd))
* improve doc comments and READMEs ([#89](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/89)) ([96e8b40](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/96e8b40f1b62b88d304244d4c340478b3e5f8373))
* reset agents brick CHANGELOG for v0.1.0 ([#83](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/83)) ([ecb927f](https://github.com/VeryGoodOpenSource/vgv_ai_cli/commit/ecb927fc6de839ee9dcbe5d94e8e2965c7568f4f))
