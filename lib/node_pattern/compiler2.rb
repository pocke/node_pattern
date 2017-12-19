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
      @match_code = compile(ast, var: Variable.new) + '|| nil'
    end

    def compile(node, var:)
      __send__ "on_#{node.type}", node, var: var
    end

    def on_node(node, var:)
      type, *rest = *node
      cur = var.cur
      if rest.empty?
        t = var.next
        return <<-RUBY.chomp
          (
            #{t} = #{cur}.type
            #{compile(type, var: var)} && #{cur}.to_a.size == 0
          )
        RUBY
      end

      <<-RUBY.chomp
        (
          (
            #{var.next} = #{cur}.type
            #{compile(type, var: var)}
          ) && (
            #{children = var.next; nil}
            #{children} = #{cur}.to_a
            #{ellipsis_idx = rest.find_index {|r| r.type == :ellipsis}
            op = ellipsis_idx ? '>=' : '=='
            sizecheck = "#{children}.size #{op} #{rest.size}"
            restcheck = rest.map.with_index do |r, idx|
              next if idx == ellipsis_idx
              v = var.next
              <<-RUBY.chomp
              (
                #{v} = #{children}[#{idx}]
                #{compile(r, var: var)}
              )
              RUBY
            end.compact
            [sizecheck, *restcheck].join('&&')}
          )
        )
      RUBY
    end

    def on_any(node, var:)
      'true'
    end

    def on_literal(node, var:)
      literal = node.to_a.first
      "(#{var.cur} == #{literal.inspect})"
    end

    def on_or(node, var:)
      <<-RUBY.chomp
        (
          #{node.to_a.map do |n|
            compile(n, var: var)
          end.join('||')}
        )
      RUBY
    end

    def on_predicate(node, var:)
      method_name = node.to_a.first
      <<-RUBY.chomp
        (
          #{var.cur}.#{method_name}
        )
      RUBY
    end

    def on_not(node, var:)
      child = node.to_a.first
      "(!#{compile(child, var: var)})"
    end
  end
end
