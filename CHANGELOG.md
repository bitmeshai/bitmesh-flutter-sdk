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
