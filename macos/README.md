# PDF Nano for Mac

A native AppKit/PDFKit application. The app uses the system PDF renderer and Apple Vision for offline OCR. PDF reading and controls use native views, with no Node runtime or HTTP server. Agent conversations containing math use one isolated WebKit view with bundled KaTeX assets; rendering makes no network requests.

## Open

Double-click `Install PDF Nano.command` to install or update `/Applications/PDF Nano.app`. Then open it from Applications, double-click `Launch PDF Nano.command`, or run `npm run mac:open`.

Launching the app directly opens the native file picker, with no intermediate Open File screen. Select one or more PDFs to start reading. Cancelling leaves the app running without a blank reader window; use Cmd+O or click the Dock icon to choose a file again. Opening a PDF from Finder goes straight to that document. The icon beside the document title uses the same PDF Nano icon as the Dock.

The installer closes the running app, lets you save changes, verifies the new package, replaces the installation, and removes this project's older app copies and Open With entries. Closing all reader windows keeps the app running in the Dock; click its Dock icon to show the file picker again. Use Cmd+Q to quit. To keep the icon after quitting, choose Dock → Options → Keep in Dock. For automatic startup, add PDF Nano in System Settings → General → Login Items.

Finder's **Open With → PDF Nano** opens PDFs in document windows. The installer does not change your default PDF app.

## Build

Requires macOS 13+ and Apple's Command Line Tools (`xcode-select --install`). The build targets the Mac's current architecture.

```sh
bash scripts/build-mac.sh
npm run mac:test
```

The native build does not require npm dependencies. With the web dependencies installed, `npm run mac:test:ocr` runs headless OCR regression checks for PDFKit selection bounds, saved multi-page search, text-layer rebuilding, original Unicode tags, page appearance, rotation, and crop coordinates. The build produces `build/PDF Nano.zip` and removes its temporary app bundle, so building does not add another Open With entry. Run `bash 'Install PDF Nano.command' --check` to validate the archive without installing. `macos/Welcome.pdf` is retained only as a smoke-test fixture. `build/` also contains compiler caches and icon intermediates.

## Controls

- **Cmd+O:** open one or more PDFs in tabs. Multiple PDFs open as tabs in one window. Select several files in the Open dialog to open them together. Each tab keeps its own reading position and unsaved edits.
- **Cmd+T:** create an empty tab. **Cmd+W:** close the current tab, with a save prompt for unsaved edits. Use **Window → Show Next Tab / Show Previous Tab** (Cmd+Shift+] / Cmd+Shift+[) to switch tabs. The tab bar’s **+** also creates a tab. Tabs can be dragged into separate windows and reunited with **Window → Merge All Windows**.
- **Sidebar / Cmd+1:** show or hide navigation. Drag the 9-point divider grip to resize it; The reader smoothly fits the available space as sidebars open or close. Thumbnails use each page’s aspect ratio, with borders, shadows, and 18-point gaps; dragging the divider continuously resizes previews. Double-click a grip to restore its default width. Column widths are remembered. Switch **Pages / Outline** to see thumbnails or the PDF's embedded chapter/section bookmarks. Root titles start 22 points from the left; children indent 12 points per level, capped at 36 points (less in narrow panes). The compact Collapse all action at the bottom of the outline closes every branch, keeping the Pages / Outline tab bar fixed in both modes; the outline context menu also offers Collapse All and Expand All. Expansion state survives reloading the same outline. Selected rows highlight across the sidebar width, including the disclosure area. With Outline open, scrolling follows the current section, including multiple sections on the same page. Entering a new section reveals its ancestors and scrolls its row into view. Manually collapsed branches stay collapsed while reading the same section, with the visible ancestor highlighted; reopening Outline reveals the current section again. The hierarchy remains expandable; embedded leading whitespace is stripped; titles wrap in full; row heights reflow when the sidebar is resized. Expand/collapse headings and click to jump. PDFs without bookmarks show an empty-outline message; headings are not inferred from page text.
- **Drag pages:** select one or more thumbnails (Cmd/Shift for multiple), then drag between thumbnails to reorder. Option-drag copies within the document. Drag to another PDF's thumbnail sidebar to copy pages, preserving the source. To place documents side by side, drag a tab into a separate window. The insertion line shows the destination.
- **Drop files:** drag images (including PNG, JPEG, TIFF, HEIC) or PDFs between thumbnails to insert pages. Dropping an image on the reader inserts it after the current page; an empty tab becomes a new PDF. Page changes support Cmd+Z / Cmd+Shift+Z and are saved with Cmd+S.
- **Zoom:** Cmd+plus or Cmd+= to enlarge, Cmd+minus to reduce, Cmd+0 to fit the page.
- **Moon beside the bottom zoom controls / View → Toggle Night Mode:** invert page and thumbnail colors for white text on black, with dark window controls and a flat footer. Page shadows are disabled in night mode to avoid bright inverted edges; the moon icon has no persistent selection background. The preference is remembered for newly opened windows and future launches. This display filter also inverts images and colored annotations; PDF content, copied text, OCR, and saved colors remain unchanged.
- **Text selection:** the default interaction; no separate cursor tool.
- **Highlighter:** select a passage, or highlight an existing text selection. You can also select text and choose Highlight from the right-click menu. Click an active tool again, double-click it, double-click the page, or press Esc to return to text selection.
- **Pen:** drag to draw a freehand annotation.
- **Note:** select text and click Note for a linked note, or choose Note and click the page for a standalone note. Clicking a note or highlight opens a compact editor beside its annotation; clicking outside dismisses it. Notes never reserve margin space or resize the page. Cmd+S stores notes in the PDF; undo/redo is supported. Delete removes a highlight’s note text and attached PDF popup while retaining the highlight, or removes a standalone note. A highlight with no note behaves as ordinary text selection; use Note on a selection or click it with Note active to add a new note. Deletion supports undo/redo and persists when saved.
- **Agent / Cmd+2:** toggle the Codex conversation panel. Click the toolbar Agent again, or the panel’s Agent title, to close it. Ask questions and follow up in the same chat. Codex begins with a short current-page excerpt and decides whether another page or a local text search is necessary. There are no scope controls. The rounded composer supports Enter to send and Shift+Enter for a new line, growing as you type. The model menu sits below the prompt beside the send button, shares the sidebar controls’ rounded style, lists installed Codex catalog models with a checkmark on the current choice, and offers Custom model… for entering an ID. The choice is remembered. Default displays the exact model ID chosen from the local catalog (explicit default, otherwise highest priority visible model), and passes that ID to Codex. Signing in refreshes available models and the exact default from Codex; if the catalog is unavailable, enter a model ID or refresh from the account menu. Stop cancels an answer. The Chat / History tabs use the same control, sizing and selection treatment as Pages / Outline and let you return to saved conversations for the current PDF, continue a thread, or delete it using its trash button. New chat starts a fresh thread without deleting previous ones. History includes interrupted questions and errors; only completed question/answer pairs are reused as model context. Answers support inline and display LaTeX, matrices, and aligned equations using bundled KaTeX 0.16.22. The native host injects the bundled scripts into an in-memory document with embedded fonts, and reads the first layout dimensions directly from the render call; initial display does not depend on hidden-view timers or file-origin resource requests. Long formulas scroll horizontally; colors follow night mode. User bubbles fit short messages, wrap at 85% width and align to the right in both native and formula conversations. Copying rendered formulas preserves LaTeX. Reopened chats render their stored source again. Invalid expressions remain readable as source, and if WebKit cannot start, the native plain-text transcript remains available.
- **Find / Cmd+F:** search document text. Enter or Cmd+G moves to the next result.
- **File → Scan Images to PDF:** create a new document from JPEG, PNG, TIFF, or HEIC files, ordered by filename. Name images `01`, `02`, etc. for explicit ordering.
- **OCR (text-viewfinder icon beside annotation tools):** scan the entire document locally with Apple Vision, processing pages in order and skipping pages that already contain selectable text. Each scanned page gains an invisible text layer for selection, copying, highlighting, and full-document Find. Word positions and typographic selection bounds keep highlights aligned with recognized text. The bottom-left status shows the current page/total and overall progress when available. Click OCR again to hide or restore progress without stopping the scan. Right-click OCR for **Stop OCR** (keeps completed pages) or **Rebuild OCR for Entire Document…** to repair older, misaligned text layers. Rebuilding converts page content to high-resolution images with fresh text layers, which can increase file size; notes and highlights remain editable. On completion, search results refresh across the document. The whole batch is one undo step. Save with Cmd+S to keep OCR text; click OCR to dismiss its completion status. Hidden progress stays hidden across pages and completion.
- **Cmd+S:** save changes. A new document asks for a destination; an opened document saves to its current file. **Shift+Cmd+S** saves a copy elsewhere.
- **Cmd+Z / Shift+Cmd+Z:** undo/redo page changes, annotations and note text.
- **Arrow keys while reading:** Left/Right go to the previous/next page; Up/Down scroll the document. Find and note editors keep normal cursor navigation.
- **Toolbar:** navigation toggle, highlighter, pen, note, OCR, Agent toggle, and Find at the right edge. Opening, saving and image import remain in File; night mode lives beside zoom controls.
- **Cmd+0:** fit page; **Cmd++ / Cmd+-:** zoom.

Native annotations (including Unicode notes) are stored inside the PDF and can be reopened. Unsaved changes prompt before closing or quitting. The app does not silently overwrite originals or autosave in place.

OCR text layers persist in the saved PDF, including rotation and crop alignment; recognition accuracy depends on scan quality. Scan supports image import, not hardware scanner control, camera capture, auto-cropping, or perspective correction. Locked/password-protected PDFs are rejected. PDF forms and signing are outside this version's scope.

## Distribution

The local build is ad-hoc signed, not notarized with an Apple Developer certificate. It is intended for this Mac. Distribution to other Macs requires an appropriate architecture build and signing/notarization. No install or Dock changes are made by the build script.

## Codex reading agent

Requires a recent installed Codex CLI supporting the account/model app-server methods and `codex exec --ignore-user-config --ephemeral` (developed against 0.172.0). Open **Agent → Sign in with ChatGPT** to authorize in your browser. A successful login returns to the chat automatically. The account icon shows the active identity, refreshes account/model information, and offers Sign out; sign out and sign in again to switch accounts. The sign-out confirmation explains that authentication is shared with the local Codex CLI. Saved chats remain local and are associated with PDFs, not cloud accounts.

On a clean Mac, Agent shows **Get Codex** (official installation instructions) and **Check again**. Codex is a separate prerequisite, not bundled in the PDF Nano archive. The app discovers it in `~/.local/bin`, Homebrew’s bin directories, or PATH. Existing Codex logins are recognized automatically. Each person's installation uses their own local credentials; no developer credentials are included. This release supports ChatGPT/Codex browser login, not Claude or other providers. PDF reading, annotations and local chat history remain available without signing in.

Account management uses the official [Codex app-server protocol](https://learn.chatgpt.com/docs/app-server) over local stdio. Only account identity and model metadata are read; PDF Nano does not read credential files or store tokens. Browser authorization stays in the system browser; cancellation, timeout and retry are supported. Signing in sends no PDF content or questions. Models are fetched after login, with the server's default first, including on machines with no previous model cache.

Only pressing Send submits a question, up to four recent exchanges, and up to 6,000 characters from the current page. The model is instructed to answer immediately when that is sufficient. It can request up to three specific pages per retrieval, additional text offsets for long pages, or a literal local search returning up to eight short excerpts. The host permits at most six retrieval rounds and 48,000 source characters per question. It never automatically uploads neighboring pages or the entire document. Requests use structured output to distinguish an answer from a request for text; unsupported requests fail without granting general tool access.

This is text-based reading: diagrams are not sent, and scanned-page questions may need OCR. General questions can still be answered without OCR. Answers can be wrong; check cited pages. Chat is saved locally to `~/Library/Application Support/PDF Nano/ChatHistory.json`, separately from the PDF. Threads are associated with the PDF’s file URL; opening the same file after restarting restores access to its history. Saving an untitled PDF transfers its chats to the saved file. Deleting a thread removes its stored messages, not the source PDF. Codex inference requires network access. The model list refreshes from Codex for the signed-in account; inaccessible model choices produce a retry message.
Requests use [Codex’s noninteractive CLI](https://learn.chatgpt.com/docs/cli/reference) in an ephemeral temporary working directory with read-only sandboxing, shell tools/apps/plugins/browser tools disabled, and user config ignored. Temporary input/output files are removed after completion, cancellation, or timeout. Both a selected model and the resolved Default are passed through `--model`, keeping the displayed model and the actual request consistent. Login and logout require explicit user actions. The app does not automatically install Codex or run document instructions.

Account regression tests use a fake local app-server and never change real credentials. They cover browser handoff, cancellation, stale login notifications, account/model refresh, pagination, missing installation, timeouts, reconnecting, and safe error messages:

```sh
xcrun swiftc -swift-version 5 -module-cache-path build/swift-cache-native macos/AgentBridge.swift macos/CodexAccount.swift tests/native/CodexAccountTests.swift -o build/codex-account-tests
build/codex-account-tests
# Optional metadata-only connection check; no login/logout or PDF prompt:
build/codex-account-tests --live-check
```

Bridge regression tests (no network required):

```sh
xcrun swiftc -swift-version 5 -module-cache-path build/swift-cache-native macos/AgentBridge.swift tests/native/AgentBridgeTests.swift -o build/agent-bridge-tests
build/agent-bridge-tests
xcrun swiftc -swift-version 5 -module-cache-path build/swift-cache-native macos/AgentBridge.swift macos/ReadingAgent.swift tests/native/ReadingAgentTests.swift -o build/reading-agent-tests
build/reading-agent-tests
xcrun swiftc -swift-version 5 -module-cache-path build/swift-cache-native macos/AgentBridge.swift macos/ChatHistory.swift tests/native/ChatHistoryTests.swift -o build/chat-history-tests
build/chat-history-tests
# Optional live test with a synthetic page, requiring Codex login/network:
build/agent-bridge-tests --live
```

Outline indentation regression check (no GUI session required):

```sh
xcrun swiftc -swift-version 5 -module-cache-path build/swift-cache-native macos/OutlineLayout.swift tests/native/OutlineLayoutTests.swift -o build/outline-layout-tests
build/outline-layout-tests
```

Outline tracking and formula regression checks:

```sh
xcrun swiftc -swift-version 5 -module-cache-path build/swift-cache-native macos/OutlineTracking.swift tests/native/OutlineTrackingTests.swift -o build/outline-tracking-tests
build/outline-tracking-tests
node tests/native/AgentMathTests.mjs
xcrun swiftc -swift-version 5 -module-cache-path build/swift-cache-native macos/AgentRendererAssets.swift tests/native/AgentRendererAssetsTests.swift -framework JavaScriptCore -o build/agent-renderer-assets-tests
build/agent-renderer-assets-tests
# Optional graphical layout check (requires Chrome and a desktop session):
node tests/native/AgentMathBrowserTests.mjs
```

Note cards now intercept page-note clicks before PDFKit's internal document view, open after the triggering event, and focus the text editor after presentation. Explicit card dimensions prevent empty popovers; each presentation has its own lifecycle so rapidly switching notes cannot clear the new editor. Native smoke tests cover sizing, reopening, old-close notifications, annotation persistence, and highlight-note deletion.
