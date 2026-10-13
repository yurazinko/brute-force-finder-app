# frozen_string_literal: true

module ResultsHelper
  def highlight_target_domain(result)
    Results::UrlHighlighter.call(result, self)
  end
end
