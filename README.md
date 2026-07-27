# bitmesh_flutter_sdk

A reusable Dart & Flutter SDK for the [Bitmesh](https://bitmesh.ai) AI API.

Bitmesh authenticates with 0-legged OAuth 1.0a plus a second SHA-256 payload
signature — fiddly enough that you don't want a copy of it in every app. This
package wraps it, adds typed models, retries, job polling and a proper exception
hierarchy, and works anywhere Dart runs.

- **Chat** completions across 90+ models
- **Image** and **video** generation, with polling for async video jobs
- **Transcription** of recorded audio, from a file path or from memory
- **Tools** (`background-removal`, `try-on-clothes`, and any other `/tools`
  endpoint) with async task polling
- Typed errors, automatic retries, injectable `http.Client`, pluggable logger
- No Flutter dependency: runs in Flutter apps (incl. web), CLIs and servers

---

## Install

```yaml
dependencies:
  bitmesh_flutter_sdk:
    git:
      url: https://github.com/bitmeshai/bitmesh-flutter-sdk.git
      ref: v0.1.0
```

Or, while developing side by side:

```yaml
dependencies:
  bitmesh_flutter_sdk:
    path: ../bitmesh-flutter-sdk
```

## Quick start

```dart
import 'package:bitmesh_flutter_sdk/bitmesh_flutter_sdk.dart';

final client = BitmeshClient.fromKeys(key, secret);

final completion = await client.chat.create(const ChatRequest(
  model: 'bitmeshai/chat-now-nano',
  messages: [
    ChatMessage.system('Reply with JSON only.'),
    ChatMessage.user('Extract the total from: COFFEE 4.50 TAX 0.36 TOTAL 4.86'),
  ],
  maxTokens: 200,
  temperature: 0.1,
));

print(completion.text);          // '{"total":"4.86"}'
print(completion.usage?.totalTokens);
```

Create **one** client and keep it: it owns a connection pool, is safe to use
concurrently, and calling `close()` is only needed when you're finished with it.

## Credentials

Never ship the key/secret inside your bundle. Load them at runtime:

```dart
// Firebase Remote Config
final client = BitmeshClient(
  credentials: BitmeshCredentials.fromMap({
    'bitmesh_key': remoteConfig.getString('bitmesh_key'),
    'bitmesh_secret': remoteConfig.getString('bitmesh_secret'),
  }),
);

// --dart-define=BITMESH_KEY=... --dart-define=BITMESH_SECRET=...
final client = BitmeshClient(credentials: BitmeshCredentials.fromEnvironment());
```

Empty or whitespace-only values throw `BitmeshConfigurationException`
immediately, instead of failing later as an opaque 401. `BitmeshCredentials`
redacts itself in `toString()`, so it is safe to log.

## Configuration

```dart
final client = BitmeshClient(
  credentials: credentials,
  options: BitmeshOptions(
    baseUrl: 'https://api.bitmesh.ai',       // point at staging or a proxy
    timeout: const Duration(seconds: 45),    // per attempt
    retryPolicy: const RetryPolicy(maxAttempts: 4),
    defaultHeaders: const {'X-App': 'spender'},
    userAgent: 'spender/2.3.1',
    logger: CallbackBitmeshLogger(debugPrint), // Flutter's debugPrint
  ),
  httpClient: myHttpClient,                  // optional, not closed by close()
);
```

## Chat

```dart
// One-shot helper
final reply = await client.chat.prompt(
  ocrText,
  model: 'bitmeshai/chat-now-nano',
  system: 'Extract transaction data. Return only JSON.',
  maxTokens: 200,
);

// Multi-turn
final chat = await client.chat.create(ChatRequest(
  model: 'bitmeshai/chat-now-nano',
  messages: [
    ChatMessage.system('You are a budgeting assistant.'),
    ChatMessage.user('How much did I spend on coffee?'),
    ChatMessage.assistant('You spent \$42 last month.'),
    ChatMessage.user('And on groceries?'),
  ],
  extra: {'top_k': 40},   // anything the SDK does not model yet
));
```

`completion.raw` always holds the untouched response body, so a new API field
never blocks you.

### Quirks worth knowing

Verified against the live API on 2026-07-27 with `bitmeshai/chat-now-nano`
(which currently resolves to `gpt-5-nano`):

- **`max_tokens` must be generous on reasoning models.** The budget is spent on
  hidden reasoning tokens *before* any visible output. `maxTokens: 10` returned
  `content: ""` with `finishReason: 'length'` and 10 reasoning tokens. If
  `completion.text` is unexpectedly `null`, check
  `completion.choices.first.finishReason` — `'length'` means raise the budget.
  A few hundred tokens is a safe floor.
- **Some models reject non-default `temperature`, and answer 500 rather than
  400.** `temperature: 0.2` produced
  `500 Unsupported value: 'temperature' does not support 0.2 with this model`,
  which surfaces as `BitmeshServerException`. Omit `temperature` unless you know
  the model accepts it. (This is also why writes don't retry 5xx by default —
  retrying would just burn attempts on a permanent error.)
- **Responses come back in camelCase** (`finishReason`, `promptTokens`) even
  though the docs show snake_case; the `test: true` debug path uses snake_case.
  The SDK reads both, so you don't have to care.
- **`completion.model` reports the resolved upstream model**
  (`gpt-5-nano-2025-08-07`), not the alias you requested.

## Images

```dart
final result = await client.images.generate(const ImageRequest(
  prompt: 'a watercolour fox reading a book',
  model: 'bitmeshai/image-now',
  width: 768,
  height: 768,
  n: 2,
));

final url = result.first?.resolveUrl(client.options.baseUrl);
// Image.network(url!)  — /imgrslt/... needs no authentication

final bytes = await client.images.download(result.first!.objectId!);
// Image.memory(bytes)
```

## Video (async job)

```dart
// Submit and wait in one call
final job = await client.video.generate(
  const VideoRequest(
    prompt: 'a paper plane gliding over a city at dusk',
    model: 'bitmeshai/video-now',
    seconds: '5',
    outputFormat: 'MP4',
  ),
  polling: const PollingOptions(
    interval: Duration(seconds: 5),
    backoffFactor: 1.5,
    timeout: Duration(minutes: 15),
  ),
  onUpdate: (job) => setState(() => status = job.rawStatus),
);
print(job.videoUrl);

// Or drive it yourself
final submitted = await client.video.create(request);
final finished = await client.video.waitFor(submitted.id);
```

## Transcription

```dart
// From a recording on disk
final job = await client.transcription.transcribe(
  BitmeshFile.fromPath(recordingPath),
  speechModels: ['whisper-large'],
);
print(job.text);

// From memory — the only option on Flutter web
final job = await client.transcription.transcribe(
  BitmeshFile.fromBytes(bytes, filename: 'note.m4a'),
);
```

## Tools

```dart
final task = await client.tools.backgroundRemoval(
  BitmeshFile.fromPath(imagePath),
  fields: {'output_format': 'png'},
);

final done = await client.tools.waitFor(task.taskId);
final cutout = await client.tools.fetchResultBytes(done.outputUrl!);

// Try-on-clothes takes several named files
await client.tools.tryOnClothes({
  'person_image': BitmeshFile.fromPath(personPath),
  'clothes_image': BitmeshFile.fromPath(clothesPath),
});

// Any other /tools endpoint
await client.tools.run('/tools/general/upscale', files: [file]);
```

## Errors

Everything thrown by the SDK extends `BitmeshException`:

```dart
try {
  final completion = await client.chat.create(request);
} on BitmeshAuthenticationException {
  // 401/403 — bad or revoked credentials
} on BitmeshRateLimitException catch (e) {
  // 429 — e.retryAfter tells you how long to wait
} on BitmeshBadRequestException catch (e) {
  // 400/422 — e.code and e.type carry the API's reason
} on BitmeshServerException {
  // 5xx, after retries were exhausted
} on BitmeshNetworkException {
  // never reached the API: offline, DNS, TLS
} on BitmeshTimeoutException {
  // exceeded BitmeshOptions.timeout
} on BitmeshException catch (e) {
  // catch-all
}
```

Job helpers add `BitmeshJobFailedException` and `BitmeshJobTimeoutException`.

## Retries

Enabled by default: 3 attempts, exponential backoff with full jitter, honouring
`Retry-After`. Every attempt is re-signed with a fresh nonce and timestamp.

| Request | Retried on |
| --- | --- |
| `GET` (safe) | network errors, timeouts, 408, 425, 429, 500, 502, 503, 504 |
| `POST` (write) | network errors, timeouts, 408, 425, 429 |

Writes deliberately do **not** retry 5xx by default: a 500 may mean the job was
created and only the response was lost, and retrying could bill you twice. Opt
in when availability matters more:

```dart
const RetryPolicy(retryWritesOnServerError: true)
const RetryPolicy.none()   // disable entirely
```

## Testing your own code

Inject a mock transport instead of hitting the network:

```dart
import 'package:http/testing.dart';

final client = BitmeshClient.fromKeys(
  'test-key',
  'test-secret',
  httpClient: MockClient((request) async => http.Response(
        '{"choices":[{"message":{"role":"assistant","content":"ok"}}]}',
        200,
        headers: {'content-type': 'application/json'},
      )),
);
```

## Platform support

| Platform | Status |
| --- | --- |
| Android / iOS / macOS / Windows / Linux | full support |
| Flutter web | full support, except `BitmeshFile.fromPath` — use `fromBytes` |
| Dart CLI / server | full support |

## Migrating from an in-app `BitmeshClient`

The old raw map-in/map-out methods still exist, so migration is mostly an import
change:

```dart
// before
final client = BitmeshClient(key, secret);
final json = await client.chat({'model': 'm', 'messages': [...]});
final video = await client.getVideo(id);

// after — identical call sites
final client = BitmeshClient.fromKeys(key, secret);
final json = await client.chat({'model': 'm', 'messages': [...]});
final video = await client.getVideo(id);
```

`chat`, `image`, `video`, `getVideo`, `transcribeFile`, `getTranscribeRecorded`,
`toolsGeneralBackgroundRemoval`, `toolsPortraitTryOnClothes`,
`toolsQueryAsyncTaskResult` and `getToolsResult` all keep their original
signatures and behaviour. Move to the typed APIs when convenient.

Behaviour that intentionally changed:

- Failures throw specific `BitmeshException` subtypes instead of bare
  `Exception`/`ArgumentError`. Catch `BitmeshException` for a like-for-like
  catch-all.
- Requests retry by default; pass `RetryPolicy.none()` for the old behaviour.
- Multipart uploads infer a `Content-Type` from the file extension instead of
  always sending `application/octet-stream`.
- List values in multipart fields are sent as `name[0]`, `name[1]`, … rather
  than a Dart `toString()` of the list. Nested maps still flatten to
  `parent[child]`, unchanged.
- Connections are pooled across calls instead of opening a new one per request.

The wire format of both signatures is unchanged — a test suite re-runs the
original signing code as a reference oracle and asserts byte-identical output.

## Development

```bash
dart pub get
dart analyze
dart test
dart run example/main.dart --key=... --secret=...
```

## Not supported yet

- Streaming chat responses (SSE). The endpoint's streaming contract isn't
  documented; `client.chat.createRaw` is the escape hatch if you need to
  experiment.
- A models-list or credits endpoint — none is documented.

## License

MIT
