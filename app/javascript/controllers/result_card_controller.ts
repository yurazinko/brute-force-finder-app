import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  appendDomCount(event: SubmitEvent): void {
    const form = event.currentTarget as HTMLFormElement | null;
    if (!form) return;

    const totalCards = document.querySelectorAll("#results_pool_list [data-result-id]").length;

    let countInput = form.querySelector('input[name="current_dom_count"]') as HTMLInputElement | null;

    if (!countInput) {
      countInput = document.createElement("input");
      countInput.type = "hidden";
      countInput.name = "current_dom_count";
      form.appendChild(countInput);
    }

    countInput.value = totalCards.toString();
  }
}