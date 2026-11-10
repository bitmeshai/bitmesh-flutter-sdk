# bitmesh_flutter_sdk

A Dart & Flutter SDK for the [Bitmesh](https://bitmesh.ai) AI API **v2**.

v2 takes one bearer key (`bmk_...`), so there is nothing to sign. This package
adds what is still worth not rewriting in every app: typed models, streaming,
retries, job polling, App Check and a proper exception hierarchy. It works
anywhere Dart runs.

- **Chat** completions across 90+ models, whole or **streamed**
- **Image** and **video** generation, with polling for async video jobs
- **Transcription** of recorded audio, from a file path or from memory
- **Tools**: background removal, virtual try-on and image-to-video
  (`image-animate`), with task polling
- The **proxy**: call OpenAI, Anthropic and other providers with a proxy key
- Firebase **App Check** for mobile keys, and debug tokens for simulators
- Typed errors, automatic retries, injectable `http.Client`, pluggable logger
- No Flutter dependency: runs in Flutter apps (incl. web), CLIs and servers

API v1 (OAuth 1.0 consumer key and secret) is not supported from 1.0.0 on. Use
0.3.0 for a v1 key, or create a v2 key in the dashboard; see
[Moving from 0.x](#moving-from-0x).

---

## Install

```yaml
dependencies:
  bitmesh_flutter_sdk:
    git:
      url: https://github.com/bitmeshai/bitmesh-flutter-sdk.git
      ref: v1.0.0
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

final client = BitmeshClient(apiKey: 'bmk_...');

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

## Keys

Create a key in the dashboard under **Keys**: **Bitmesh hosts the model** for
chat, images and the other endpoints, or **I bring my provider key** for the
proxy. Choose **In my mobile app** for a key that ships in an app (it then
requires App Check), or **On my server** (optionally limited to your servers'
IP addresses).

Never hardcode the key. Load it at runtime:

```dart
// Firebase Remote Config
final client = BitmeshClient(apiKey: remoteConfig.getString('bitmesh_key'));

// --dart-define=BITMESH_KEY=bmk_...
final client = BitmeshClient(
  apiKey: const String.fromEnvironment('BITMESH_KEY'),
);
```

An empty key, or one that doesn't start with `bmk_` (a v1 consumer key),
throws `BitmeshConfigurationException` straight away instead of failing later
as a 401. The SDK never logs the key.

## Configuration

```dart
final client = BitmeshClient(
  credentials: credentials,
  options: BitmeshOptions(
    baseUrl: 'https://api.bitmesh.ai',       // the SDK adds /v2
    timeout: const Duration(seconds: 45),    // per attempt
    retryPolicy: const RetryPolicy(maxAttempts: 4),
    defaultHeaders: const {'X-App': 'spender'},
    userAgent: 'spender/2.3.1',
    logger: CallbackBitmeshLogger(debugPrint), // Flutter's debugPrint
  ),
  httpClient: myHttpClient,                  // optional, not closed by close()
);
```

## App Check (mobile keys)

If your key ships inside an iOS or Android app, create it as a **mobile app**
key in the Bitmesh dashboard. The API then refuses any request on that key
that doesn't carry a valid [Firebase App Check](https://firebase.google.com/docs/app-check)
token, so a key extracted from your app binary is useless on its own.
Server keys don't need this; leave the option unset.

Set up App Check for your apps in the Firebase console first (Play Integrity on
Android, App Attest on iOS, debug tokens for emulators). The full walkthrough
is in the [API docs](https://bitmesh.ai/docs#app-check). Then hand the SDK a
token provider:

```dart
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

await Firebase.initializeApp();
await FirebaseAppCheck.instance.activate(
  // Debug provider in debug builds ONLY. Never ship it in a release.
  providerAndroid:
      kDebugMode ? AndroidDebugProvider() : AndroidPlayIntegrityProvider(),
  providerApple: kDebugMode ? AppleDebugProvider() : AppleAppAttestProvider(),
);

final client = BitmeshClient(
  credentials: credentials,
  options: BitmeshOptions(
    appCheckTokenProvider: () => FirebaseAppCheck.instance.getToken(),
  ),
);
```

- The provider is called before **every** request, retries and job
  polling included. Firebase caches the token and refreshes it before it
  expires, so this is cheap. Don't cache tokens yourself.
- The token goes in the `X-Firebase-AppCheck` header. The SDK never logs it.
- Public result downloads (`images.download`, tool results) don't send it.
- This package doesn't depend on Firebase: any function returning a token
  works, which keeps plain Dart and tests free of plugins.

### Debug tokens

On a simulator, or before Firebase is set up, a Bitmesh debug token
(`bmdbg_...`, created on the key in the dashboard) can stand in for App Check.
It is sent as `X-Bitmesh-Debug-Token`, and the token provider isn't called.
Pick it by build mode so it never reaches a release:

```dart
final client = BitmeshClient(
  apiKey: key,
  options: BitmeshOptions(
    debugToken: kDebugMode ? const String.fromEnvironment('BITMESH_DEBUG_TOKEN') : null,
    appCheckTokenProvider: () => FirebaseAppCheck.instance.getToken(),
  ),
);
```

### Failures

Failures are typed:

```dart
try {
  await client.chat.create(request);
} on BitmeshAppCheckTokenException catch (e) {
  // No token on the device, so nothing was sent. e.cause holds the Firebase
  // error. Usually App Check isn't set up for this app in the Firebase console.
} on BitmeshAppCheckRejectedException catch (e) {
  // 401: the API refused the token (or debug token). e.message names the
  // reason, e.g.
  // "App Check token is for an unregistered app". e.isTemporary is true only
  // when the API couldn't verify tokens at all; retry later in that case.
}
```

`BitmeshAppCheckRejectedException` extends `BitmeshAuthenticationException`,
so existing 401 handlers still catch it.

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

### Streaming

```dart
final reply = StringBuffer();
await for (final chunk in client.chat.stream(request)) {
  reply.write(chunk.text);              // new text, '' on bookkeeping chunks
  setState(() => answer = reply.toString());
  if (chunk.usage != null) print(chunk.usage); // last chunk: billed tokens
}

// Or collect it, with a callback per piece
final text = await client.chat.streamText(request, onText: (t) => print(t));
```

The request is billed once, when the stream ends. Cancel the subscription (or
`break` out of the loop) to stop generating; you pay only for what was written.
`BitmeshOptions.timeout` covers the wait for the reply to start, not its
length. Errors before the stream starts throw as usual; a provider failure
mid-stream throws `BitmeshApiException`.

### Things worth knowing

- **`max_tokens` must be generous on reasoning models.** The budget is spent on
  hidden reasoning tokens *before* any visible output. With `maxTokens: 10`
  the reply can be `content: ""` with `finish_reason: 'length'`. If
  `completion.text` is unexpectedly `null`, check
  `completion.choices.first.finishReason`: `'length'` means raise the budget.
  A few hundred tokens is a safe floor.
- **Some models reject non-default `temperature`, and answer 500 rather than
  400.** That surfaces as `BitmeshServerException`. Omit `temperature` unless
  you know the model accepts it. (This is also why writes don't retry 5xx by
  default.)
- **`completion.model` reports the resolved upstream model**
  (`gpt-5-nano-2025-08-07`), not the alias you requested.
- Replies use OpenAI's snake_case field names for every model, so
  `completion.raw` reads like any OpenAI response.

## Balance

```dart
final credits = await client.balance();   // GET /v2/balance
await client.verify();                    // GET /v2/test: throws if the key
                                          // or App Check token is refused
```

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
// Background removal answers straight away with the result link
final cutout = await client.tools.backgroundRemoval(
  BitmeshFile.fromPath(imagePath),
  fields: {'return_form': 'crop'}, // or 'mask', 'whiteBK'; leave out for a transparent PNG
);
final png = await client.tools.fetchResultBytes(cutout.outputUrl!);

// Try-on returns a task: poll it until the picture is ready
final job = await client.tools.tryOnClothes(
  {
    'person_image': BitmeshFile.fromPath(personPath),
    'top_garment': BitmeshFile.fromPath(shirtPath),
    // 'bottom_garment': BitmeshFile.fromPath(trousersPath),
  },
  fields: {'restore_face': true, 'resolution': 1024},
);
final dressed = await client.tools.waitFor(
  job.taskId,
  // Each poll counts toward the key's requests a minute
  options: const PollingOptions(interval: Duration(seconds: 10)),
);
final picture = await client.tools.fetchResultBytes(dressed.outputUrl!);

// Image-to-video: the image goes base64-encoded in a JSON body
final animation = await client.tools.imageAnimate(
  model: 'animate-2.4-faster', // or 'animate-2.4-advanced'
  image: BitmeshFile.fromPath(imagePath),
  seconds: 5, // 1 to 10
  prompt: 'the cat slowly blinks',
  aspectRatio: '9:16', // optional: 16:9, 9:16, 1:1, 4:3, 3:4
);
final video = await client.tools.waitForImageAnimate(animation.taskId);
print(video.outputUrl); // signed link, valid for about 8 hours
```

Multipart form fields travel as text. The SDK sends booleans as `"1"` / `"0"`
and numbers as their string form, and leaves out `null`s. Result links can point at the tool provider's own storage and expire,
so download what you want to keep.

## Proxy

With a proxy key, send the provider's own request, minus its API key header:
Bitmesh adds your stored provider key. Bodies and replies pass through
unchanged.

```dart
final proxy = BitmeshClient(apiKey: proxyKey);

final reply = await proxy.proxy.post('openai', 'v1/chat/completions', {
  'model': 'gpt-4o-mini',
  'messages': [{'role': 'user', 'content': 'Hello'}],
});

// Provider headers that select options are passed on
final message = await proxy.proxy.post(
  'anthropic',
  'v1/messages',
  {'model': 'claude-sonnet-4-5', 'max_tokens': 256, 'messages': [...]},
  headers: {'anthropic-version': '2023-06-01'},
);

// Streaming: the provider's server-sent events, as they arrive
await for (final event in proxy.proxy.stream('openai', 'v1/chat/completions', body)) {
  if (event.isDone) break;
  final delta = event.json()['choices'][0]['delta']['content'];
}

// The whole response, headers included
final response = await proxy.proxy.send('openai', 'v1/models');
print(response.requestId); // X-Bitmesh-Request-Id
```

## Errors

Everything thrown by the SDK extends `BitmeshException`:

```dart
try {
  final completion = await client.chat.create(request);
} on BitmeshAppCheckRejectedException catch (e) {
  // 401 — mobile key: App Check token missing or refused (see App Check)
} on BitmeshAuthenticationException {
  // 401/403: bad, revoked or v1 key, or an address outside the allowlist
} on BitmeshInsufficientBalanceException {
  // 402: out of credits (proxy keys: no active plan)
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
} on BitmeshAppCheckTokenException {
  // the App Check token provider failed, so nothing was sent
} on BitmeshException catch (e) {
  // catch-all
}
```

Job helpers add `BitmeshJobFailedException` and `BitmeshJobTimeoutException`.

## Retries

Enabled by default: 3 attempts, exponential backoff with full jitter, honouring
`Retry-After`. Every attempt fetches a fresh App Check token.

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

final client = BitmeshClient(
  apiKey: 'bmk_test',
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

## Moving from 0.x

1.0.0 talks to API v2 only. Request bodies, models, limits and prices are the
same as v1; what changes is the key and the client:

```dart
// 0.x, v1
final client = BitmeshClient.fromKeys(consumerKey, consumerSecret);

// 1.0, v2
final client = BitmeshClient(apiKey: 'bmk_...');
```

- Create a v2 key in the dashboard. A v1 key is refused on v2 and the other
  way round.
- `BitmeshCredentials`, `OAuth1Signer` and the map-in/map-out compat methods
  (`client.chat({...})`, `getVideo`, `transcribeFile`, `toolsPortraitTryOnClothes`,
  ...) are gone. Use the typed APIs, or `createRaw` / `getRaw` for raw maps.
- Replies are always snake_case, so `completion.raw` no longer has camelCase
  fields such as `usage.promptTokens`.
- New: `chat.stream`, `proxy`, `balance()`, `verify()`,
  `BitmeshOptions.debugToken` and `BitmeshInsufficientBalanceException` (402).

## Development

```bash
dart pub get
dart analyze
dart test
dart run example/main.dart --key=bmk_... [--debug-token=bmdbg_...]
```

## Not supported

- API v1 (OAuth 1.0 signing). Use 0.3.0.
- A models-list endpoint: none is documented.

## License

MIT
