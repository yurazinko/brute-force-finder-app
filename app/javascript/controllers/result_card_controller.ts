import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
appendDomCount(event) {
  const form = event.target
  const feedContainer = document.querySelector("#results_pool_list")
  const currentDomCount = feedContainer ? feedContainer.children.length : 0

  if (currentDomCount > 0) {
    const actionUrl = new URL(form.action, window.location.origin)
    actionUrl.searchParams.set("current_dom_count", currentDomCount)
    form.action = actionUrl.toString()
  }
}
}