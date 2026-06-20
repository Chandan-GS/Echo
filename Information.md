# Project ECHO - Master Blueprint

## Phase 0: The Onboarding Journey (UI Layer)

**1. The Permission Hub (Screen 1)**
The user opens the app for the first time. They are greeted with a security-focused UI (lock icons, privacy badges). 

- **Flow:** The UI triggers a series of permission checks using `permission_handler`. 
- **Action:** For Notification Access, the UI cannot grant this directly. It launches an **Android Intent** (`Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS`) redirecting the user to the system settings to manually toggle "Echo" on. 
- **State:** The UI polls the system to confirm the toggle. Only when all permissions (Notifications, Calendar, SMS) are green does the "Continue" button unlock.

**2. The AI Mode Selector (Screen 1, bottom sheet)**
The user chooses how they want the brain to work:

- **Option A (Offline):** The UI triggers a background download of the 2.5GB Phi-3 model from your CDN. A progress bar stays on screen until the file is verified (checksum validation). 
- **Option B (Online - BYOK):** The UI reveals a masked text field. The user pastes their OpenAI or Gemini API key. The UI sends a test ping (a dummy API call) to validate the key. If valid, the app encrypts it using Android Keystore via `flutter_secure_storage` and saves the encrypted string to Isar's `AppSettings` table. 

---

## Phase 1: The Daytime Listening (Data Capture Layer)

**3. The Native Broadcast Receiver (Android OS Level)**
Now that permissions are granted, the Android system treats "Echo" as a trusted accessibility component. 

- **Event:** A WhatsApp message arrives. Android's `NotificationManagerService` receives the incoming GCM/FCM push. 
- **Interception:** Because the user enabled Notification Access, Android forks a lightweight native process for your `NotificationListenerService` and invokes `onNotificationPosted()`.
- **Extraction:** The native Kotlin code queries the `extras` bundle to pull `EXTRA_TITLE` (sender), `EXTRA_TEXT` (message body), and `getPackageName()` (com.whatsapp). 

**4. The Bridge to Flutter (EventChannel)**
The Kotlin service does **not** wait for Flutter to be awake. 

- It serializes the extracted data into a small JSON string.
- It pushes this JSON into an **EventChannel** buffer. Android handles this buffer natively, even if the Flutter UI is killed.
- When the user opens the app (or when the background isolate warms up), Flutter's EventChannel listener drains this buffer.

**5. The Local Persistence (Isar Write)**
Flutter receives the JSON. 

- It deserializes it into a `RawData` Isar entity.
- It writes it to the local database with a `timestamp`. 
- **Crucial Logic:** The UI does not rebuild on every single WhatsApp ping (that would drain the battery). The `RawDataRepository` simply silently appends this to the collection. By 10 PM, you might have 40-50 `RawData` entries stored locally.

**6. The Midnight Reset (Background Scheduled Job)**
At 10:00 PM, a `Workmanager` task fires. 

- Its sole purpose is **data hygiene**. 
- It queries Isar for any `RawData` older than 24 hours and deletes them. This ensures your local database never exceeds ~5,000 records, keeping the vector search snappy.

---

## Phase 2: The Pre-Dawn Machine (Background Processing Layer)

**7. The Alarm Clock Wake-up (WorkManager)**
At 6:55 AM, the Android `AlarmManager` (triggered by WorkManager with `setExactAndAllowWhileIdle`) wakes the device. 

- **Foreground Service:** Since this task takes > 1 minute, the app immediately spins up a foreground service. The user sees a persistent notification: *"Echo is composing your briefing..."* (This prevents Android 14 from killing the process).

**8. Data Aggregation (The Context Builder)**
Flutter's background isolate queries the `RawDataRepository`:

- It requests: *"Give me all RawData where timestamp is between 00:00 AM today and NOW."*
- It limits this to the **top 50 most recent** entries to fit inside the LLM's context window. 

**9. Semantic Compression (Local Embedding + RAG)**
We don't just dump 50 messages into the LLM (too expensive/computationally heavy). We compress them.

- The background isolate loads the lightweight `all-MiniLM-L6-v2.tflite` model.
- It splits the 50 messages into 5 logical chunks (approx 800 characters each).
- It runs inference on TFLite to convert each chunk into a **384-dimension embedding vector**.
- It has a hardcoded "Priority Query" vector inside the app: *"What requires immediate action, involves family, or relates to deadlines?"*
- It performs a **brute-force cosine similarity** calculation in pure Dart/Isar between the Priority Query vector and the 5 chunk vectors. It picks the **Top 2 chunks** with the highest similarity. (This reduces 50 messages down to ~1,600 characters of high-signal text).

---

## Phase 3: The Branching Intelligence (Hybrid AI Pipeline)

**10. The Decision Gateway (Cubit Logic)**
The background isolate checks the `AppSettings` singleton:

- **Does `isCloudMode == true` and `encryptedApiKey` exist?**
  - **YES (Online Mode):** 
    - The isolate decrypts the API key.
    - It constructs a System Prompt: *"You are a private assistant. Summarize these texts into a 20-second spoken briefing."*
    - It opens an HTTP (Dio) connection to `api.openai.com` or `generativelanguage.googleapis.com`.
    - **Network Optimization:** It streams the response. The LLM generates the text in ~3-5 seconds. 
    - **Cost:** ~$0.002 per request (user pays via their own key).
  
  - **NO (Offline Mode):**
    - The isolate loads the 2.5GB `Phi-3.Q4_K_M.gguf` file from internal storage into memory via `flutter_llama_cpp` (FFI binding to C++).
    - It constructs the same prompt.
    - The CPU runs inference at ~8-12 tokens/second. The user waits ~20-30 seconds for the response.
    - **State update:** The Cubit emits a `GenerationLoading(progress: 0.8)` state to optionally update the UI (if the user is watching).

**11. The Sanitizer**
Regardless of the branch, the raw LLM output is received (e.g., *"Good morning. John sent a contract amendment at 6 PM..."*).

- A simple Dart regex strips out any markdown (`**`, `#`) or emojis (to ensure clean TTS).
- The final `String` is ready.

---

## Phase 4: Audio Rendering & Local Storage (Media Layer)

**12. Text-to-Speech Synthesis**
The background isolate calls `flutter_tts`.

- It sets the language to `en-US` and speed to `0.85x` (calm, morning tone).
- Instead of playing it live, it calls `tts.synthesizeToFile(summary, 'briefing_${today}.wav')`.
- Android's native TTS engine (which runs offline) renders the audio and saves the file to the app's `ApplicationDocumentsDirectory`.

**13. Saving the Master Record**
The isolate creates a `Briefing` Isar entity:

- `textSummary` (the raw LLM text).
- `audioFilePath` (absolute path to the .wav file).
- `generatedAt` (timestamp).
- It writes this to Isar.

**14. The Cleanup**
To save RAM for the user's other apps, the background isolate closes the LLM model handles (unloads the .gguf from memory if offline mode was used) and disposes of the TFLite interpreter.

---

## Phase 5: The Push & User Awakening (Notification Layer)

**15. The Heads-Up Notification**
Flutter's background isolate uses `flutter_local_notifications` to send a **high-priority** push notification.

- **Title:** "Your Echo Briefing is ready."
- **Body:** First 30 characters of the summary.
- **Payload:** `{ "briefing_id": "123" }`.
- **Action:** Android displays this as a heads-up banner (pop-up), waking the screen if it's locked.

**16. The Foreground Service Termination**
The `Workmanager` task officially ends. The persistent "composing" notification disappears, replaced by the new "briefing ready" notification. The phone goes back to deep sleep.

---

## Phase 6: Consumption (UI Presentation Layer)

**17. User Taps the Notification**
Flutter's `onDidReceiveNotificationResponse` callback is triggered.

- The UI navigates to `BriefingPlayerScreen(briefingId: 123)`.

**18. The Player Screen Loads**
The `PlayerCubit` fires up.

- It queries the `BriefingRepository` to fetch the full entity using the ID.
- It loads the audio file path into the `audioplayers` widget and pre-caches it.
- It loads the `textSummary` into a `RichText` widget.
- **The Waveform:** It reads the raw .wav bytes and passes them to the `audio_waveforms` package to render a static waveform visualization.

**19. Playback & Karaoke Sync**
The user presses "Play".

- `audioplayers` streams the current position every 100ms.
- The UI calculates: *"At 3.2 seconds, the player is at 20% of the total duration."*
- It highlights the corresponding 20% segment of the `RichText` in a neon blue color and auto-scrolls the `SingleChildScrollView` to keep that line centered.
- The waveform pulses with the audio amplitude.

---

## Phase 7: The "Vault" (Transparency Screen)

**20. The Privacy Showcase**
The user navigates to the "Vault" screen.

- The UI simply listens to the `RawDataRepository.watch()` stream.
- Because Isar supports real-time streams, the UI instantly populates a list showing: *"WhatsApp - John - 2:30 PM - 'Hey, are we meeting?'"*
- If the user is paranoid, they can swipe-left on a record to delete it permanently from Isar (which also means that record will never be used in the next morning's RAG).

---

## Phase 8: The Edge Cases (Failure Recovery)

- **What if the phone restarts at 6:50 AM?** 
  - WorkManager has a built-in `setBackoffCriteria()`. It will retry the job when the phone boots up and the battery is > 20%.

- **What if the Offline LLM crashes halfway through (Out of Memory)?** 
  - The `GenerationCubit` catches the native FFI exception and emits a `GenerationError`. 
  - **Recovery:** The Cubit falls back to a "Mini-Briefing"—it skips the LLM and just concatenates the Top 2 chunks into a plain text sentence. It sends the notification anyway, preventing the user from waking up to silence.

- **What if the user revokes Notification Access?** 
  - The app does not crash. The Home Dashboard shows a red "Access Disabled" banner. The UI prompts them to re-enable it. Without new data, the 7 AM job runs but finds `RawData` empty, and generates a briefing: *"No new updates were captured today."*

---

## Summary Data Flow Matrix

| Stage | Trigger | Data Transformation | Persistence |
| :--- | :--- | :--- | :--- |
| **Capture** | WhatsApp Push | JSON -> RawData Entity | Isar |
| **Embed** | 6:55 AM Cron | 50 Texts -> 5 Chunks -> 5 Vectors (384-dim) | In-memory only |
| **Retrieve** | RAG Engine | 5 Vectors -> Top 2 Sorted by Cosine Similarity | In-memory only |
| **Generate** | Cubit Logic | Top 2 Chunks -> LLM (Cloud/Local) -> Summary String | In-memory only |
| **Synthesize** | TTS Engine | Summary String -> briefing.wav (Audio) | App Documents Directory |
| **Archive** | End of Job | Briefing Entity (Text + Path) | Isar |
| **Consume** | User Tap | Briefing Entity + .wav | UI / AudioPlayer |

---

## Phase 9: Echo Converse (Interactive RAG)

**21. Mock Data Seeding (Testing Foundation)**
During development, the Isar database is populated with realistic mock notifications (work messages, personal texts, calendar events). Each entry is pre-embedded using a local embedding model, and the resulting 384-dimensional vector is stored alongside the text in Isar.

**22. The Embedding & Indexing Workflow**
In production, when a new notification arrives via the `NotificationListenerService`, the raw text is extracted. Before saving to Isar, an on-device embedding model (e.g. `all-MiniLM-L6-v2`) converts the text into a vector. Both the raw text and vector are saved in a single atomic transaction.

**23. The "Converse" Retrieval (RAG)**
When the user asks a question in the "Converse" screen:
- The query is embedded into a 384-dimensional vector.
- The app fetches candidate `RawData` entries from Isar.
- A brute-force cosine similarity calculation is performed between the query vector and candidate vectors.
- The top 3-5 most relevant entries (with similarity > 0.5) are retrieved and concatenated to form the context.

**24. Converse Prompt Engineering**
A strict system prompt is used:
- **Role:** "You are Echo, a private assistant. Answer using ONLY the provided context."
- The retrieved context and the user's query are injected into the prompt.
- The total prompt length is kept under the LLM's context window limits.

**25. Inference & Streaming**
The prompt is fed to the initialized local model (e.g. Gemma or DeepSeek). The UI streams the response token-by-token for a fast, responsive user experience. If the user asks a new question mid-generation, the current inference is cancelled and restarted.

**26. UI/UX for the Converse Screen**
A minimal chat interface matching the app's aesthetic:
- Accessible via an "Ask Echo" button on the Dashboard.
- Features a scrollable list of message bubbles, a fixed text input at the bottom, and state indicators for "Searching..." and "Typing...".
- Includes empty state suggestions and graceful error handling if no relevant context is found.
