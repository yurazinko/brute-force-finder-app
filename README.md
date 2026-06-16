# Brute Force Finder

**Brute Force Finder** is a high-performance, asynchronous job/lead aggregation, filtering, and real-time monitoring platform. Unlike conventional rigid scrapers, this app utilizes a cascade pipeline architecture: data collection via private/anonymous search infrastructures, intelligent prompt processing, and instant delivery of results to the frontend using persistent connections without full page reloads.

---

## Architecture and Tech Stack

The project is built following the principle of a minimalist yet powerful monolith, focusing heavily on speed, extreme resilience, and seamless UX:

* **Backend:** Ruby on Rails (v8+) utilizing hybrid HTML/Turbo Stream rendering.
* **Frontend:** Tailwind CSS + Hotwire (**Turbo Streams, Turbo Frames, Stimulus JS**). Zero heavy SPA overhead - the interface is fully reactive out of the box via WebSockets.
* **Background Processing:** Sidekiq (concurrent queues handles all scraping jobs asynchronously).
* **Real-time Engine:** ActionCable (WebSockets) for point-to-point live broadcasting of UI counters and new content.
* **Scraping Core:** Integrated with a local instance of **SearXNG** (privacy-respecting meta-search engine).
* **Anonymity/Anti-Ban:** Routing all outbound search engine traffic through the **Tor Network** with automatic exit node rotation.

---

## Key Features and UX Patterns

### 1. Cascade Pipeline Execution (Lifecycle)
Every global search request is decomposed into atomic prompt records targeted at specific job categories/domains. The system fires up async workers, tracks the live status of each thread, and dynamically reflects the pipeline state on the frontend

### 2. "Inbox Zero" and Graceful Removal
To provide a friction-free experience when triaging large pools of data, the UI implements a smart delayed-removal pattern:
* The **Inbox** tab strictly shows new (`Unread`) and `Interesting` leads, filtering out `Watched` and `Garbage`.
* When clicking *"Mark Watched"* inside the Inbox, the card **does not vanish instantly** (preventing jarring layout shifts and allowing quick undoing). Instead, it gracefully fades out.
* Buttons shift instantly allowing you to still change your mind or immediately toss it to *"Mark as Garbage"*. The card disappears from the Inbox view completely **only after** you change tabs or hit refresh. On the **Watched** tab itself, cards render at full 100% opacity.

### 3. Fully Decoupled and Atomized Live Counters (DRY Streams)
Any data mutations (marking elements, background engine injecting results) execute atomic `Turbo::StreamsChannel` updates. They touch specific DOM IDs (like tab counts and result pools) for all connected clients instantly, completely bypassing heavy recount database queries (`COUNT(*)`) during rendering.

---

## Infrastructure and Local Docker Topology

The application environment runs fully isolated via Docker Compose, bridging the following micro-services:

1. `finder_rails` — The core Web/App monolithic process.
2. `sidekiq` — Asynchronous background job worker pool.
3. `finder_searxng` — Private meta-search engine configured with zero tracking, serving as our gateway to major search engines.
4. `tor` — Anonymity SOCKS5 proxy layer. `searxng` routes traffic exclusively through it to safeguard your host IP from rate limits and blocks.

---

## Quick Start

1. Build the image:
   ```console
   docker-compose build
   ```

2. Install the dependencies and prepare the database:

   ```console
   docker-compose run app bundle install
   docker-compose run app bundle exec rails db:setup
   ```

3. Launch the application:

   ```console
   docker-compose up