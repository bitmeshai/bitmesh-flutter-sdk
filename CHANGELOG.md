## 0.2.0

- Firebase App Check support for mobile API keys. Set
  `BitmeshOptions.appCheckTokenProvider` and the SDK sends a fresh token in
  `X-Firebase-AppCheck` on every signed request, retries and polling included.
  The token is outside both signatures and is never logged. The package still
  has no Firebase dependency.
- `BitmeshAppCheckTokenException`: the provider threw or returned no token, so
  the request was not sent.
- `BitmeshAppCheckRejectedException` (a `BitmeshAuthenticationException`): the
  API answered 401 because the token was missing or failed verification.
  `isTemporary` flags the API-side outage case worth retrying.

## 0.1.0

Initial release, extracted and generalised from an in-app `BitmeshClient`.

- OAuth 1.0a (0-legged) signing + `X-Payload-Signature` for every request.
- Namespaced APIs: `chat`, `images`, `video`, `transcription`, `tools`.
- Typed request/response models with a `raw` escape hatch on every response.
- Typed exception hierarchy (`BitmeshApiException` and friends).
- Configurable base URL, timeout, headers, logger and retry policy.
- Automatic retries with exponential backoff, jitter and `Retry-After` support.
- Built-in polling helpers for async jobs (`video`, `transcription`, `tools`).
- Cross-platform uploads via `BitmeshFile` (path or in-memory bytes).
- Injectable `http.Client` for connection reuse and testing.
- Response parsing accepts both camelCase and snake_case keys: the live API
  answers real requests in camelCase while the docs and the `test: true` debug
  path use snake_case.

Verified against the live `/chat` endpoint on 2026-07-27. Payloads captured from
that run are pinned in `test/api_payloads_test.dart`.
