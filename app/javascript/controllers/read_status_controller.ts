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

    const card = link.closest(".flex.flex-col.gap-2") as HTMLElement
    if (card) {
      card.classList.add("opacity-60")
    }

    fetch(url, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": this.getCsrfToken(),
        "Accept": "text/html; turbo-stream",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
    .then(response => {
      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`)
      return response.text()
    })
    .then(html => {
      const holder = document.createElement("div")
      holder.innerHTML = html
      document.body.appendChild(holder)
      holder.remove()
    })
    .catch(error => {
      console.error("Error marking as read:", error)
      // if (card) card.classList.remove("opacity-60")
    })
  }

  private getCsrfToken(): string {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.getAttribute("content") || "" : ""
  }
}


