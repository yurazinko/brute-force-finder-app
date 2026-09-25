import BulkSelectorController from "./bulk_selector_controller"

export default class extends BulkSelectorController {
  protected getActiveText(): string {
    return "Clear Group"
  }

  protected getInactiveText(): string {
    return "Select All"
  }

  protected getActiveClasses(): string {
    return "category-bulk-btn text-[10px] font-mono bg-breeze-accent/20 border border-breeze-accent/40 text-breeze-accent px-2 py-0.5 rounded font-medium transition cursor-pointer shadow-2xs"
  }

  protected getInactiveClasses(): string {
    return "category-bulk-btn text-[10px] font-mono bg-breeze-view border border-breeze-border text-breeze-muted hover:text-breeze-text hover:bg-breeze-border/40 px-2 py-0.5 rounded font-medium transition cursor-pointer"
  }
}