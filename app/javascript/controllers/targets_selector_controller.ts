import BulkSelectorController from "./bulk_selector_controller"

export default class extends BulkSelectorController {
  protected getActiveText(): string { return "Clear Group" }
  protected getInactiveText(): string { return "Select All Group" }

  protected getActiveClasses(): string {
    return "category-bulk-btn text-[11px] bg-gray-200 border border-gray-400 text-breeze-text px-2 py-0.5 rounded shadow-inner font-medium transition cursor-pointer"
  }

  protected getInactiveClasses(): string {
    return "category-bulk-btn text-[11px] bg-breeze-view border border-breeze-border text-breeze-text hover:bg-breeze-bg px-2 py-0.5 rounded shadow-sm font-medium transition cursor-pointer"
  }
}