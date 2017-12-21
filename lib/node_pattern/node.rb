module NodePattern
  class Node < AST::Node
    def ellipsis?
      type == :ellipsis
    end

    def capture?
      type == :capture
    end
  end
end
