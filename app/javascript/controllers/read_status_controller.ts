import { Controller } from "@hotwired/stimulus"

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

    const card = link.closest(".flex.flex-col.gap-2") as HTMLElement
    if (card) {
      card.classList.add("opacity-60")
    }

    // Готуємо дані у правильному Rails-форматі
    const bodyData = {
      result: {
        status: "watched"
      },
      // Якщо контролеру потрібні ці параметри для рендеру Turbo Stream відповіді,
      // ми можемо передати їх поруч
      current_tab: link.getAttribute("data-current-tab") || "unread",
      status_filter: "watched"
    }

    fetch(url, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": this.getCsrfToken(),
        "Content-Type": "application/json", // Додаємо заголовок типу контенту
        "Accept": "text/html; turbo-stream",
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify(bodyData) // Передаємо дані в тілі запиту
    })
    .then(response => {
      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`)
      return response.text()
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
