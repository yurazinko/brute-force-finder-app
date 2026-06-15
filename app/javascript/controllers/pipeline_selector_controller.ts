import BulkSelectorController from "./bulk_selector_controller"

export default class extends BulkSelectorController {
  protected getActiveText(): string { return "Clear Group" }
  protected getInactiveText(): string { return "Select Group" }

  protected getActiveClasses(): string {
    return "group-toggle-btn text-[10px] text-gray-500 hover:underline font-medium cursor-pointer"
  }

  protected getInactiveClasses(): string {
    return "group-toggle-btn text-[10px] text-indigo-600 hover:underline font-semibold cursor-pointer"
  }
}