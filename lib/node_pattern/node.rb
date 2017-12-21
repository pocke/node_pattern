module NodePattern
  class Node < AST::Node
    def ellipsis?
      type == :ellipsis || (capture? && children.first.ellipsis?)
    end

    def capture?
      type == :capture
    end
  end
end
