import BulkSelectorController from "./bulk_selector_controller"

export default class extends BulkSelectorController {
  protected getActiveText(): string { return "Clear Group" }
  protected getInactiveText(): string { return "Select All Group" }

  protected getActiveClasses(): string {
    return "category-bulk-btn text-[11px] bg-gray-200 border border-gray-400 text-gray-800 px-2 py-0.5 rounded shadow-inner font-medium transition cursor-pointer"
  }

  protected getInactiveClasses(): string {
    return "category-bulk-btn text-[11px] bg-white border border-gray-300 text-gray-700 hover:bg-gray-100 px-2 py-0.5 rounded shadow-sm font-medium transition cursor-pointer"
  }
}