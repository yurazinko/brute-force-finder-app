import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Use native capture listeners instead of Stimulus data-action descriptors.
  // A context-click is a sequence of low-level mouse events; listening in the
  // capture phase on the card makes the interaction independent of the target
  // element's own handlers and preserves the browser's native context menu.
  private readonly handleInteraction = (event: Event): void => {
    if (!(event instanceof MouseEvent)) return

    const eventTarget = event.target
    const target = eventTarget instanceof Element
      ? eventTarget
      : eventTarget instanceof Node
        ? eventTarget.parentElement
        : null

    const link = target?.closest<HTMLAnchorElement>("a[data-read-url]")
    if (!link || !this.element.contains(link)) return

    switch (event.type) {
      case "click":
        if (event.button !== 0) return
        event.preventDefault()
        window.open(link.href, "_blank", "noopener,noreferrer")
        break
      case "pointerdown":
      case "mousedown":
        // Right mouse button: mark immediately on pointer/mouse down, before
        // the browser opens its native context menu.
        if (event.button !== 2) return
        break
      case "auxclick":
        // Preserve native middle-/right-click behavior; only update the status.
        if (event.button !== 1 && event.button !== 2) return
        break
      case "contextmenu":
        // Keep the native context menu available to the user.
        if (event.button !== 2) return
        break
      default:
        return
    }

    this.markLinkAsRead(link)
  }

  connect(): void {
    // Capture on the card root so the handler runs before any target/bubble
    // handlers on the title link. `data-action` is deliberately not involved.
    this.element.addEventListener("pointerdown", this.handleInteraction, true)
    this.element.addEventListener("mousedown", this.handleInteraction, true)
    this.element.addEventListener("click", this.handleInteraction, true)
    this.element.addEventListener("auxclick", this.handleInteraction, true)
    this.element.addEventListener("contextmenu", this.handleInteraction, true)
    this.element.setAttribute("data-read-status-ready", "true")
  }

  disconnect(): void {
    this.element.removeEventListener("pointerdown", this.handleInteraction, true)
    this.element.removeEventListener("mousedown", this.handleInteraction, true)
    this.element.removeEventListener("click", this.handleInteraction, true)
    this.element.removeEventListener("auxclick", this.handleInteraction, true)
    this.element.removeEventListener("contextmenu", this.handleInteraction, true)
    this.element.removeAttribute("data-read-status-ready")
  }

  private markLinkAsRead(link: HTMLAnchorElement): void {
    const url = link.getAttribute("data-read-url")
    const status = link.getAttribute("data-read-status")
    const previousStatus = status || "unread"

    // Treat a missing status as unread, but do not send duplicate requests once
    // an earlier event in the same right-click sequence has updated the link.
    if (status && status !== "unread") return
    if (!url) return

    // Update the DOM synchronously. pointerdown, mousedown, auxclick and
    // contextmenu can all be emitted for one physical right-click.
    link.setAttribute("data-read-status", "watched")
    this.element.classList.add("opacity-50", "transition-opacity", "duration-500")
    this.element.setAttribute("data-read-status-current-status-value", "watched")
    this.element.removeAttribute("data-read-status-saved")
    this.updateCounters(true)

    const bodyData = {
      result: { status: "watched" },
      current_tab: link.getAttribute("data-current-tab") || "unread",
      status_filter: "watched"
    }

    fetch(url, {
      method: "PATCH",
      credentials: "same-origin",
      headers: {
        "X-CSRF-Token": this.getCsrfToken(),
        "Content-Type": "application/json",
        "Accept": "text/html",
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify(bodyData)
    })
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP ${response.status} while marking ${url} as reviewed`)
        }

        // This marker is set only after the server has persisted the status.
        // System specs can wait for it instead of racing the asynchronous PATCH.
        this.element.setAttribute("data-read-status-saved", "true")
      })
      .catch(error => {
        link.setAttribute("data-read-status", previousStatus)
        this.element.setAttribute("data-read-status-current-status-value", previousStatus)
        this.element.removeAttribute("data-read-status-saved")
        this.element.classList.remove("opacity-50", "transition-opacity", "duration-500")
        this.updateCounters(false)
        console.error("Could not mark result as reviewed:", error)
      })
  }

  private updateCounters(markedAsRead: boolean): void {
    const unreadEl = document.getElementById("counter_unread")
    const watchedEl = document.getElementById("counter_watched")
    const delta = markedAsRead ? 1 : -1

    if (unreadEl) {
      const currentUnread = Number.parseInt(unreadEl.textContent || "0", 10)
      unreadEl.textContent = Math.max(0, currentUnread - delta).toString()
    }

    if (watchedEl) {
      const currentWatched = Number.parseInt(watchedEl.textContent || "0", 10)
      watchedEl.textContent = Math.max(0, currentWatched + delta).toString()
    }
  }

  private getCsrfToken(): string {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta?.getAttribute("content") || ""
  }
}
