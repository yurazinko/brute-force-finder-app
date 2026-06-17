# Brute Force Finder

**Brute Force Finder** is your autonomous assistant for continuous web monitoring, job hunting, and lead generation. It is designed for professionals who are tired of manual searching, dealing with endless algorithmic noise, and wasting hours re-evaluating the same low-quality results. Instead of browsing multiple platforms daily, you define your targets once. The system runs in the background, continuously filters the spam, and delivers a clean, actionable stream of fresh opportunities.
---

## The Problems It Solves
- Search Fatigue and Burnout: Manually tracking 5+ platforms with different keywords takes hours. This platform automates the entire process.

- The "Deja Vu" Effect (Persistent Spam): The biggest pain of manual search is seeing the same outdated listings, scam links, or irrelevant results every single day.

- Rate Limits and IP Blocks: Aggressive searching triggers captchas, paywalls, and temporary IP bans from major search engines or job boards.

---

## Key User Features
#### "Inbox Zero" Triage
The system acts like a smart email client. The Inbox strictly displays leads you have never seen before.

- One-Click Dismissal: Spotted a bad result? Hit "Mark as Garbage" or "Mark Watched".

- Permanent Blacklisting: Once dismissed, that specific result is muted forever. Even if the scraper encounters it again next week, it will never clutter your Inbox again. Your feed becomes cleaner over time.

#### Graceful UI Feedback
Elements never vanish abruptly from under your cursor. Marking a lead as watched smoothly dims the card. This gives you immediate visual confirmation while keeping the controls active, allowing you to quickly undo the action or instantly toss it into "Garbage" if you change your mind. The card disappears completely only when you refresh or switch tabs.

#### The "Gold Standard" Shortlist
Isolate top-tier opportunities instantly. The "Interesting" tab acts as your dedicated shortlist, allowing you to archive high-value leads for personalized outreach (e.g., tailored cover letters or cold emails) while the background engine keeps processing the rest.

#### Zero-Track Anonymity
By routing 100% of outbound metadata queries through the Tor Network, external platforms cannot track your actual IP, log your search behavior, or serve you manipulated, hyper-personalized search results. To the web, your scraper looks like thousands of organic users worldwide.


## Architecture and Tech Stack

Unlike conventional rigid scrapers, this app utilizes a cascade pipeline architecture: data collection via anonymous search infrastructures, intelligent prompt processing, and instant delivery of results to the frontend.

The project is built following the principle of a minimalist yet powerful monolith, focusing heavily on speed, extreme resilience, and seamless UX:

* **Backend:** Ruby on Rails (v8+) utilizing hybrid HTML/Turbo Stream rendering.
* **Frontend:** Tailwind CSS + Hotwire (**Turbo Streams, Turbo Frames, Stimulus JS**). Minimum SPA overhead - the interface is fully reactive out of the box via WebSockets.
* **Background Processing:** Sidekiq (concurrent queues handles all scraping jobs asynchronously).
* **Real-time Engine:** ActionCable (WebSockets) for point-to-point live broadcasting of UI counters and new content.
* **Scraping Core:** Integrated with a local instance of **SearXNG** (privacy-respecting meta-search engine).
* **Anonymity/Anti-Ban:** Routing all outbound search engine traffic through the **Tor Network** with automatic exit node rotation.
---

## Infrastructure and Topology

The application environment runs fully isolated via Docker Compose, bridging the following micro-services:

1. `finder_rails` — The core Web/App monolithic process.
2. `sidekiq` — Asynchronous background job worker pool.
3. `finder_searxng` — Private meta-search engine configured with zero tracking, serving as our gateway to major search engines.
4. `tor` — Anonymity SOCKS5 proxy layer. `searxng` routes traffic exclusively through it to safeguard your host IP from rate limits and blocks.

---

## Quick Start

1. Clone the repo:

  ```console
  git clone [https://github.com/yurazinko/brute-force-finder-app.git](https://github.com/yurazinko/brute-force-finder-app.git)
  cd brute-force-finder-app
  ```

2. Build the image:
   ```console
   docker-compose build
   ```

3. Install the dependencies and prepare the database:

   ```console
   docker-compose run app bundle install
   docker-compose run app bundle exec rails db:setup
   ```

4. Launch the application:

   ```console
   docker-compose up

Once ready, navigate to: [http://localhost:3000](http://localhost:3000)
