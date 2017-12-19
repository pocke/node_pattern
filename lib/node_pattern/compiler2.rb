module NodePattern
  class Compiler2
    class Variable
      def initialize
        @count = 0
      end

      def next
        @count += 1
        cur
      end

      def cur
        "var#{@count}"
      end

      alias branch dup
    end

    def initialize(pattern)
      @pattern   = pattern

      run
    end

    attr_reader :match_code

    private

    attr_reader :pattern

    def run
      parser = Parser.new(pattern)
      ok = parser.parse
      parser.raise_error unless ok
      ast = parser.ast
      @match_code = compile(ast, var: Variable.new)
    end

    def compile(node, var:)
      __send__ "on_#{node.type}", node, var: var
    end

    def on_node(node, var:)
      type, *rest = *node
      cur = var.cur
      if rest.empty?
        return <<~RUBY
          #{cur}.type == #{type.inspect}
        RUBY
      end

      children = var.next
      <<~RUBY
        #{cur}.type == #{type.inspect} && (
          #{children} = #{cur}.to_a
          #{children}.size == #{rest.size} &&
            #{rest.map.with_index do |r, idx|
              v = var.next
              <<~RUBY
                (
                  #{v} = #{children}[#{idx}]
                  #{compile(r, var: var)}
                )
              RUBY
            end.join('&&')}
        )
      RUBY
    end

    def on_any(node, var:)
      'true'
    end
  end
end
