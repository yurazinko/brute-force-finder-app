import BulkSelectorController from "./bulk_selector_controller"

export default class extends BulkSelectorController {
  protected getActiveText(): string { return "Clear Group" }
  protected getInactiveText(): string { return "Select Group" }

  protected getActiveClasses(): string {
    return "group-toggle-btn text-[10px] text-breeze-muted hover:underline font-medium cursor-pointer"
  }

  protected getInactiveClasses(): string {
    return "group-toggle-btn text-[10px] text-breeze-accent hover:underline font-semibold cursor-pointer"
  }
}