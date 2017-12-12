class NodePattern
  # @private
  # Builds Ruby code which implements a pattern
  class Compiler
    SYMBOL       = %r{:(?:[\w+@*/?!<>=~|%^-]+|\[\]=?)}
    IDENTIFIER   = /[a-zA-Z_-]/
    META         = /\(|\)|\{|\}|\[|\]|\$\.\.\.|\$|!|\^|\.\.\./
    NUMBER       = /-?\d+(?:\.\d+)?/
    STRING       = /".+?"/
    METHOD_NAME  = /\#?#{IDENTIFIER}+[\!\?]?\(?/
    PARAM_NUMBER = /%\d*/

    SEPARATORS = /[\s]+/
    TOKENS     = Regexp.union(META, PARAM_NUMBER, NUMBER,
                              METHOD_NAME, SYMBOL, STRING)

    TOKEN = /\G(?:#{SEPARATORS}|#{TOKENS}|.)/

    NODE      = /\A#{IDENTIFIER}+\Z/
    PREDICATE = /\A#{IDENTIFIER}+\?\(?\Z/
    WILDCARD  = /\A_#{IDENTIFIER}*\Z/
    FUNCALL   = /\A\##{METHOD_NAME}/
    LITERAL   = /\A(?:#{SYMBOL}|#{NUMBER}|#{STRING})\Z/
    PARAM     = /\A#{PARAM_NUMBER}\Z/
    CLOSING   = /\A(?:\)|\}|\])\Z/

    attr_reader :match_code

    def initialize(str, node_var = 'node0')
      @string   = str
      @root     = node_var

      @temps    = 0  # avoid name clashes between temp variables
      @captures = 0  # number of captures seen
      @unify    = {} # named wildcard -> temp variable number
      @params   = 0  # highest % (param) number seen

      run(node_var)
    end

    def run(node_var)
      tokens =
        @string.scan(TOKEN).reject { |token| token =~ /\A#{SEPARATORS}\Z/ }

      @match_code = compile_expr(tokens, node_var, false)

      fail_due_to('unbalanced pattern') unless tokens.empty?
    end

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def compile_expr(tokens, cur_node, seq_head)
      # read a single pattern-matching expression from the token stream,
      # return Ruby code which performs the corresponding matching operation
      # on 'cur_node' (which is Ruby code which evaluates to an AST node)
      #
      # the 'pattern-matching' expression may be a composite which
      # contains an arbitrary number of sub-expressions
      token = tokens.shift
      case token
      when '('       then compile_seq(tokens, cur_node, seq_head)
      when '{'       then compile_union(tokens, cur_node, seq_head)
      when '['       then compile_intersect(tokens, cur_node, seq_head)
      when '!'       then compile_negation(tokens, cur_node, seq_head)
      when '$'       then compile_capture(tokens, cur_node, seq_head)
      when '^'       then compile_ascend(tokens, cur_node, seq_head)
      when WILDCARD  then compile_wildcard(cur_node, token[1..-1], seq_head)
      when FUNCALL   then compile_funcall(tokens, cur_node, token, seq_head)
      when LITERAL   then compile_literal(cur_node, token, seq_head)
      when PREDICATE then compile_predicate(tokens, cur_node, token, seq_head)
      when NODE      then compile_nodetype(cur_node, token)
      when PARAM     then compile_param(cur_node, token[1..-1], seq_head)
      when CLOSING   then fail_due_to("#{token} in invalid position")
      when nil       then fail_due_to('pattern ended prematurely')
      else                fail_due_to("invalid token #{token.inspect}")
      end
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    def compile_seq(tokens, cur_node, seq_head)
      fail_due_to('empty parentheses') if tokens.first == ')'
      fail_due_to('parentheses at sequence head') if seq_head

      # 'cur_node' is a Ruby expression which evaluates to an AST node,
      # but we don't know how expensive it is
      # to be safe, cache the node in a temp variable and then use the
      # temp variable as 'cur_node'
      with_temp_node(cur_node) do |init, temp_node|
        terms = compile_seq_terms(tokens, temp_node)

        join_terms(init, terms, ' && ')
      end
    end

    def compile_seq_terms(tokens, cur_node)
      ret, size =
        compile_seq_terms_with_size(tokens, cur_node) do |token, terms, index|
          case token
          when '...'.freeze
            return compile_ellipsis(tokens, cur_node, terms, index)
          when '$...'.freeze
            return compile_capt_ellip(tokens, cur_node, terms, index)
          end
        end

      ret << "(#{cur_node}.children.size == #{size})"
    end

    def compile_seq_terms_with_size(tokens, cur_node)
      index = nil
      terms = []
      until tokens.first == ')'
        yield tokens.first, terms, index || 0
        term, index = compile_expr_with_index(tokens, cur_node, index)
        terms << term
      end

      tokens.shift # drop concluding )
      [terms, index]
    end

    def compile_expr_with_index(tokens, cur_node, index)
      if index.nil?
        # in 'sequence head' position; some expressions are compiled
        # differently at 'sequence head' (notably 'node type' expressions)
        # grep for seq_head to see where it makes a difference
        [compile_expr(tokens, cur_node, true), 0]
      else
        child_node = "#{cur_node}.children[#{index}]"
        [compile_expr(tokens, child_node, false), index + 1]
      end
    end

    def compile_ellipsis(tokens, cur_node, terms, index)
      if (term = compile_seq_tail(tokens, "#{cur_node}.children.last"))
        terms << "(#{cur_node}.children.size > #{index})"
        terms << term
      elsif index > 0
        terms << "(#{cur_node}.children.size >= #{index})"
      end
      terms
    end

    def compile_capt_ellip(tokens, cur_node, terms, index)
      capture = next_capture
      if (term = compile_seq_tail(tokens, "#{cur_node}.children.last"))
        terms << "(#{cur_node}.children.size > #{index})"
        terms << term
        terms << "(#{capture} = #{cur_node}.children[#{index}..-2])"
      else
        terms << "(#{cur_node}.children.size >= #{index})" if index > 0
        terms << "(#{capture} = #{cur_node}.children[#{index}..-1])"
      end
      terms
    end

    def compile_seq_tail(tokens, cur_node)
      tokens.shift
      if tokens.first == ')'
        tokens.shift
        nil
      else
        expr = compile_expr(tokens, cur_node, false)
        fail_due_to('missing )') unless tokens.shift == ')'
        expr
      end
    end

    def compile_union(tokens, cur_node, seq_head)
      fail_due_to('empty union') if tokens.first == '}'

      with_temp_node(cur_node) do |init, temp_node|
        terms = union_terms(tokens, temp_node, seq_head)
        join_terms(init, terms, ' || ')
      end
    end

    def union_terms(tokens, temp_node, seq_head)
      # we need to ensure that each branch of the {} contains the same
      # number of captures (since only one branch of the {} can actually
      # match, the same variables are used to hold the captures for each
      # branch)
      compile_expr_with_captures(tokens,
                                 temp_node, seq_head) do |term, before, after|
        terms = [term]
        until tokens.first == '}'
          terms << compile_expr_with_capture_check(tokens, temp_node,
                                                   seq_head, before, after)
        end
        tokens.shift

        terms
      end
    end

    def compile_expr_with_captures(tokens, temp_node, seq_head)
      captures_before = @captures
      expr = compile_expr(tokens, temp_node, seq_head)

      yield expr, captures_before, @captures
    end

    def compile_expr_with_capture_check(tokens, temp_node, seq_head, before,
                                        after)
      @captures = before
      expr = compile_expr(tokens, temp_node, seq_head)
      if @captures != after
        fail_due_to('each branch of {} must have same # of captures')
      end

      expr
    end

    def compile_intersect(tokens, cur_node, seq_head)
      fail_due_to('empty intersection') if tokens.first == ']'

      with_temp_node(cur_node) do |init, temp_node|
        terms = []
        until tokens.first == ']'
          terms << compile_expr(tokens, temp_node, seq_head)
        end
        tokens.shift

        join_terms(init, terms, ' && ')
      end
    end

    def compile_capture(tokens, cur_node, seq_head)
      "(#{next_capture} = #{cur_node}#{'.type' if seq_head}; " \
        "#{compile_expr(tokens, cur_node, seq_head)})"
    end

    def compile_negation(tokens, cur_node, seq_head)
      "(!#{compile_expr(tokens, cur_node, seq_head)})"
    end

    def compile_ascend(tokens, cur_node, seq_head)
      "(#{cur_node}.parent && " \
        "#{compile_expr(tokens, "#{cur_node}.parent", seq_head)})"
    end

    def compile_wildcard(cur_node, name, seq_head)
      if name.empty?
        'true'
      elsif @unify.key?(name)
        # we have already seen a wildcard with this name before
        # so the value it matched the first time will already be stored
        # in a temp. check if this value matches the one stored in the temp
        "(#{cur_node}#{'.type' if seq_head} == temp#{@unify[name]})"
      else
        n = @unify[name] = next_temp_value
        # double assign to temp#{n} to avoid "assigned but unused variable"
        "(temp#{n} = #{cur_node}#{'.type' if seq_head}; " \
        "temp#{n} = temp#{n}; true)"
      end
    end

    def compile_literal(cur_node, literal, seq_head)
      "(#{cur_node}#{'.type' if seq_head} == #{literal})"
    end

    def compile_predicate(tokens, cur_node, predicate, seq_head)
      if predicate.end_with?('(') # is there an arglist?
        args = compile_args(tokens)
        predicate = predicate[0..-2] # drop the trailing (
        "(#{cur_node}#{'.type' if seq_head}.#{predicate}(#{args.join(',')}))"
      else
        "(#{cur_node}#{'.type' if seq_head}.#{predicate})"
      end
    end

    def compile_funcall(tokens, cur_node, method, seq_head)
      # call a method in the context which this pattern-matching
      # code is used in. pass target value as an argument
      method = method[1..-1] # drop the leading #
      if method.end_with?('(') # is there an arglist?
        args = compile_args(tokens)
        method = method[0..-2] # drop the trailing (
        "(#{method}(#{cur_node}#{'.type' if seq_head}),#{args.join(',')})"
      else
        "(#{method}(#{cur_node}#{'.type' if seq_head}))"
      end
    end

    def compile_nodetype(cur_node, type)
      "(#{cur_node} && #{cur_node}.type == #{type.to_sym.inspect})"
    end

    def compile_param(cur_node, number, seq_head)
      "(#{cur_node}#{'.type' if seq_head} == #{get_param(number)})"
    end

    def compile_args(tokens)
      args = []
      args << compile_arg(tokens.shift) until tokens.first == ')'
      tokens.shift # drop the )
      args
    end

    def compile_arg(token)
      case token
      when WILDCARD  then
        name   = token[1..-1]
        number = @unify[name] || fail_due_to('invalid in arglist: ' + token)
        "temp#{number}"
      when LITERAL   then token
      when PARAM     then get_param(token[1..-1])
      when CLOSING   then fail_due_to("#{token} in invalid position")
      when nil       then fail_due_to('pattern ended prematurely')
      else fail_due_to("invalid token in arglist: #{token.inspect}")
      end
    end

    def next_capture
      "capture#{@captures += 1}"
    end

    def get_param(number)
      number = number.empty? ? 1 : Integer(number)
      @params = number if number > @params
      number.zero? ? @root : "param#{number}"
    end

    def join_terms(init, terms, operator)
      "(#{init};#{terms.join(operator)})"
    end

    def emit_capture_list
      (1..@captures).map { |n| "capture#{n}" }.join(',')
    end

    def emit_retval
      if @captures.zero?
        'true'
      elsif @captures == 1
        'capture1'
      else
        "[#{emit_capture_list}]"
      end
    end

    def emit_param_list
      (1..@params).map { |n| "param#{n}" }.join(',')
    end

    def emit_trailing_params
      params = emit_param_list
      params.empty? ? '' : ",#{params}"
    end

    def emit_guard_clause
      <<-RUBY
        return unless node.is_a?(RuboCop::AST::Node)
      RUBY
    end

    def emit_method_code
      <<-RUBY
        return unless #{@match_code}
        block_given? ? yield(#{emit_capture_list}) : (return #{emit_retval})
      RUBY
    end

    def fail_due_to(message)
      raise Invalid, "Couldn't compile due to #{message}. Pattern: #{@string}"
    end

    def with_temp_node(cur_node)
      with_temp_variable do |temp_var|
        # double assign to temp#{n} to avoid "assigned but unused variable"
        yield "#{temp_var} = #{cur_node}; #{temp_var} = #{temp_var}", temp_var
      end
    end

    def with_temp_variable
      yield "temp#{next_temp_value}"
    end

    def next_temp_value
      @temps += 1
    end
  end
end
