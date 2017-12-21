module NodePattern
  # Helpers for defining methods based on a pattern string
  module Macros
    # Define a method which applies a pattern to an AST node
    #
    # The new method will return nil if the node does not match
    # If the node matches, and a block is provided, the new method will
    # yield to the block (passing any captures as block arguments).
    # If the node matches, and no block is provided, the new method will
    # return the captures, or `true` if there were none.
    def def_node_matcher(method_name, pattern_str)
      compiler = Compiler.new(pattern_str, 'node')
      src = "def #{method_name}(node = self" \
            "#{compiler.emit_trailing_params});" \
            "#{compiler.emit_guard_clause}" \
            "#{compiler.emit_method_code};end"

      location = caller_locations(1, 1).first
      class_eval(src, location.path, location.lineno)
    end

    # Define a method which recurses over the descendants of an AST node,
    # checking whether any of them match the provided pattern
    #
    # If the method name ends with '?', the new method will return `true`
    # as soon as it finds a descendant which matches. Otherwise, it will
    # yield all descendants which match.
    def def_node_search(method_name, pattern_str)
      compiler = Compiler.new(pattern_str, 'node')
      called_from = caller(1..1).first.split(':')

      if method_name.to_s.end_with?('?')
        node_search_first(method_name, compiler, called_from)
      else
        node_search_all(method_name, compiler, called_from)
      end
    end

    def node_search_first(method_name, compiler, called_from)
      node_search(method_name, compiler, 'return true', '', called_from)
    end

    def node_search_all(method_name, compiler, called_from)
      yieldval = compiler.emit_capture_list
      yieldval = 'node' if yieldval.empty?
      prelude = "return enum_for(:#{method_name}, node0" \
                "#{compiler.emit_trailing_params}) unless block_given?"

      node_search(method_name, compiler, "yield(#{yieldval})", prelude,
                  called_from)
    end

    def node_search(method_name, compiler, on_match, prelude, called_from)
      src = node_search_body(method_name, compiler.emit_trailing_params,
                             prelude, compiler.match_code, on_match)
      filename, lineno = *called_from
      class_eval(src, filename, lineno.to_i)
    end

    def node_search_body(method_name, trailing_params, prelude, match_code,
                         on_match)
      <<-RUBY
        def #{method_name}(node0#{trailing_params})
          #{prelude}
          node0.each_node do |node|
            if #{match_code}
              #{on_match}
            end
          end
          nil
        end
      RUBY
    end
  end
end
