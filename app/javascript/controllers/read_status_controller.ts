import { Controller } from "@hotwired/stimulus"
import { renderStreamMessage } from "@hotwired/turbo"

export default class extends Controller {
  markAsRead(event: MouseEvent) {
    const link = event.currentTarget as HTMLElement
    const url = link.getAttribute("data-read-url")
    const status = link.getAttribute("data-read-status")

    if (status !== "unread" && status !== "") return
    if (!url) return

    if (event.type === "click") {
      event.preventDefault()
      window.open(link.getAttribute("href") || "", "_blank", "noopener,noreferrer")
    } else if (event.type === "contextmenu") {
      event.stopPropagation()
    } else {
      return
    }

    this.optimisticUpdateCounters()
    link.setAttribute("data-read-status", "watched")

    const card = (link.closest('[data-controller*="read-status"]') ||
                  link.closest('.flex.flex-col.gap-2\.5') ||
                  link.closest('.flex.flex-col.gap-2')) as HTMLElement

    if (card) {
      card.classList.add("opacity-50", "transition-opacity", "duration-500")
    }

    const bodyData = {
      result: {
        status: "watched"
      },
      current_tab: link.getAttribute("data-current-tab") || "unread"
    }

    fetch(url, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": this.getCsrfToken(),
        "Content-Type": "application/json",
        "Accept": "text/vnd.turbo-stream.html",
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify(bodyData)
    })
      .then((response) => {
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`)
        }

        return response.text()
      })
      .then((streamHtml) => renderStreamMessage(streamHtml))
      .catch((error) => {
        console.error("Failed to mark result as read", error)
      })
  }

  private optimisticUpdateCounters(): void {
    const unreadEl = document.getElementById("counter_unread")
    const watchedEl = document.getElementById("counter_watched")

    const step = 1

    if (unreadEl) {
      const currentUnread = parseInt(unreadEl.textContent || "0", 10)
      unreadEl.textContent = Math.max(0, currentUnread - step).toString()
    }

    if (watchedEl) {
      const currentWatched = parseInt(watchedEl.textContent || "0", 10)
      watchedEl.textContent = Math.max(0, currentWatched + step).toString()
    }
  }

  private getCsrfToken(): string {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.getAttribute("content") || "" : ""
  }
}
