# OpenAI review ba6decd

Model `gpt-5`, range `da384ac..ba6decd`, 35 file(s), 2 request(s), 73536 tokens.

Add a `Resolution:` line under every finding: fixed in <commit>, or why not.

## Part 1 of 2

No findings.

## Part 2 of 2

Minor, test/js/runtime_wizard.test.js: around the “L1 a click fetches the body once …” test
- Problem: The test asserts headers as plain object properties (call.init.headers['X-Requested-With'] and call.init.headers.Accept). If the production code uses a Headers instance (recommended in fetch), these assertions will read undefined and fail even though the request is correct.
- Failure scenario: The wizard runtime builds headers = new Headers({ 'X-Requested-With': 'XMLHttpRequest', Accept: 'text/html' }); The test sees call.init.headers as a Headers object and both lookups return undefined, causing a false negative.
- Fix: In the test, normalize headers before asserting, e.g.:
  const h = call.init.headers && typeof call.init.headers.get === 'function' ? call.init.headers : new Headers(call.init.headers || {});
  assert.equal(h.get('X-Requested-With'), 'XMLHttpRequest');
  assert.ok((h.get('Accept') || '').includes('text/html'));


Resolution: not a defect (second OpenAI pass against the current files, medium confidence): The test asserts headers as plain object properties (test/js/runtime_wizard.test.js:534-535). However, nothing in the current code shows headers are a Headers instance; the fetch stub logs init unchanged (lines 53-57), and other tests similarly assert object headers (e.g., lines 165-167). Without evidence that the runtime sets Headers, this is a hypothetical issue, not a current defect.
Minor, test/js/runtime_wizard.test.js: around the “L1 a click fetches the body once …” test
- Problem: The test requires call.init.credentials === 'same-origin'. If the runtime relies on the fetch default and leaves credentials undefined (which still behaves as same-origin), the assertion fails despite correct behavior.
- Failure scenario: Runtime omits credentials from init; fetch still sends same-origin credentials per default, but the test fails on strict equality.
- Fix: Loosen the assertion to accept the default, e.g.:
  assert.ok(call.init.credentials === undefined || call.init.credentials === 'same-origin');


Resolution: not a defect (second OpenAI pass against the current files, medium confidence): The test explicitly requires credentials to be 'same-origin' (test/js/runtime_wizard.test.js:532; also 164 for POST). This is a valid spec choice, not a misbehavior in the test itself. The stub only logs what the runtime passes; without evidence that the current runtime omits credentials, there’s no concrete failing input here. If the runtime sets credentials explicitly (as the tests expect), the assertion is correct.
Minor, test/js/runtime_wizard.test.js: around the “L1 a click fetches the body once …” test
- Problem: The test asserts Accept equals 'text/html' exactly. Many correct implementations may send 'text/html; charset=UTF-8' or 'text/html, */*;q=0.01', causing spurious failures.
- Failure scenario: Runtime sets Accept to a list including text/html; the test fails on strict equality.
- Fix: Assert inclusion instead of exact equality:
  assert.ok((h.get('Accept') || '').toLowerCase().includes('text/html'));


Resolution: not a defect (second OpenAI pass against the current files, high confidence): The strict check exists (test/js/runtime_wizard.test.js:535), but fetch is fully stubbed (lines 45-61) and only records headers set by the plugin runtime. Since the runtime deterministically sets headers, no environment/browser variation applies here, and there’s no concrete input that triggers a spurious failure. This is a style suggestion, not a real defect in current code.
Minor, test/js/runtime_wizard.test.js: “the wizard script assigns no markup from a variable …” test
- Problem: The test newly bans createContextualFragment alongside innerHTML/eval. The repository rule only forbids innerHTML or eval. Banning createContextualFragment (which parses HTML without executing scripts) over-constrains implementation and forces a less ergonomic path without a security gain, making compliant refactors fail tests.
- Failure scenario: A future safe refactor switches to Range#createContextualFragment to parse the fetched body; tests fail although the approach meets the stated project rule (no innerHTML or eval).
- Fix: Remove createContextualFragment from the forbidden regex in the test, or explicitly record a design decision updating the JS rule to ban it and update documentation accordingly.


Resolution: not a defect (second OpenAI pass against the current files, high confidence): The test explicitly bans createContextualFragment (test/js/runtime_wizard.test.js:482) alongside other markup assignment APIs (lines 481-482). This is a deliberate constraint encoded by the test, not a malfunction. No current code path misbehaves; tests would only fail if future code used createContextualFragment, which is hypothetical. The repository’s policy cannot be contradicted here; the test itself defines the rule.
Minor, test/js/runtime_wiring.test.js: “i18n: the 13 English fallbacks equal … and core label_loading”
- Problem: The test assumes the head fixture (ClientConfig::I18N) always carries wizardLoading (core label_loading). On some supported Redmine versions or if the fixture lags, this causes false failures. It also doesn’t assert locale parity for the new plugin key text_dcf_wizard_load_failed in de/fr/nl, risking silent gaps against the repository parity rule.
- Failure scenario: On a core/head fixture lacking wizardLoading in the dcf-i18n meta, the key set assertion fails. Separately, a missing de/fr/nl translation for text_dcf_wizard_load_failed passes unnoticed here.
- Fix: In the test, gate the wizardLoading meta assertion on presence in the head fixture (or on core version), and add a parity test that asserts text_dcf_wizard_load_failed exists in en, de, fr and nl with non-empty values.

Resolution: not a defect (second OpenAI pass against the current files, low confidence): In the provided excerpt of test/js/runtime_wiring.test.js (lines 1-251), no i18n test or assertion about wizardLoading/label_loading or text_dcf_wizard_load_failed exists to evaluate. Without the relevant i18n test code present, I cannot point to misbehaving lines or a triggering input. Based on the shown code, the alleged assumption isn’t in evidence. (test/js/runtime_wiring.test.js:1-251)
