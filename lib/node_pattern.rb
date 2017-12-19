require 'ast'
require "node_pattern/version"
require 'node_pattern/compiler'
require 'node_pattern/macros'
require 'node_pattern/parser.kpeg.rb'

# This class performs a pattern-matching operation on an AST node.
#
# Initialize a new `NodePattern` with `NodePattern.new(pattern_string)`, then
# pass an AST node to `NodePattern#match`. Alternatively, use one of the class
# macros in `NodePattern::Macros` to define your own pattern-matching method.
#
# If the match fails, `nil` will be returned. If the match succeeds, the
# return value depends on whether a block was provided to `#match`, and
# whether the pattern contained any "captures" (values which are extracted
# from a matching AST.)
#
# - With block: #match yields the captures (if any) and passes the return
#               value of the block through.
# - With no block, but one capture: the capture is returned.
# - With no block, but multiple captures: captures are returned as an array.
# - With no block and no captures: #match returns `true`.
#
# ## Pattern string format examples
#
#     ':sym'              # matches a literal symbol
#     '1'                 # matches a literal integer
#     'nil'               # matches a literal nil
#     'send'              # matches (send ...)
#     '(send)'            # matches (send)
#     '(send ...)'        # matches (send ...)
#     '(op-asgn)'         # node types with hyphenated names also work
#     '{send class}'      # matches (send ...) or (class ...)
#     '({send class})'    # matches (send) or (class)
#     '(send const)'      # matches (send (const ...))
#     '(send _ :new)'     # matches (send <anything> :new)
#     '(send $_ :new)'    # as above, but whatever matches the $_ is captured
#     '(send $_ $_)'      # you can use as many captures as you want
#     '(send !const ...)' # ! negates the next part of the pattern
#     '$(send const ...)' # arbitrary matching can be performed on a capture
#     '(send _recv _msg)' # wildcards can be named (for readability)
#     '(send ... :new)'   # you can specifically match against the last child
#                         # (this only works for the very last)
#     '(send $...)'       # capture all the children as an array
#     '(send $... int)'   # capture all children but the last as an array
#     '(send _x :+ _x)'   # unification is performed on named wildcards
#                         # (like Prolog variables...)
#                         # (#== is used to see if values unify)
#     '(int odd?)'        # words which end with a ? are predicate methods,
#                         # are are called on the target to see if it matches
#                         # any Ruby method which the matched object supports
#                         # can be used
#                         # if a truthy value is returned, the match succeeds
#     '(int [!1 !2])'     # [] contains multiple patterns, ALL of which must
#                         # match in that position
#                         # in other words, while {} is pattern union (logical
#                         # OR), [] is intersection (logical AND)
#     '(send %1 _)'       # % stands for a parameter which must be supplied to
#                         # #match at matching time
#                         # it will be compared to the corresponding value in
#                         # the AST using #==
#                         # a bare '%' is the same as '%1'
#                         # the number of extra parameters passed to #match
#                         # must equal the highest % value in the pattern
#                         # for consistency, %0 is the 'root node' which is
#                         # passed as the 1st argument to #match, where the
#                         # matching process starts
#     '^^send'            # each ^ ascends one level in the AST
#                         # so this matches against the grandparent node
#     '#method'           # we call this a 'funcall'; it calls a method in the
#                         # context where a pattern-matching method is defined
#                         # if that returns a truthy value, the match succeeds
#     'equal?(%1)'        # predicates can be given 1 or more extra args
#     '#method(%0, 1)'    # funcalls can also be given 1 or more extra args
#
# You can nest arbitrarily deep:
#
#     # matches node parsed from 'Const = Class.new' or 'Const = Module.new':
#     '(casgn nil const (send (const nil {:Class :Module}) :new)))'
#     # matches a node parsed from an 'if', with a '==' comparison,
#     # and no 'else' branch:
#     '(if (send _ :== _) _ nil)'
#
# Note that patterns like 'send' are implemented by calling `#send_type?` on
# the node being matched, 'const' by `#const_type?`, 'int' by `#int_type?`,
# and so on. Therefore, if you add methods which are named like
# `#prefix_type?` to the AST node class, then 'prefix' will become usable as
# a pattern.
#
# Also note that if you need a "guard clause" to protect against possible nils
# in a certain place in the AST, you can do it like this: `[!nil <pattern>]`
#
# The compiler code is very simple; don't be afraid to read through it!
class NodePattern
  # @private
  Invalid = Class.new(StandardError)

  def initialize(str)
    compiler = Compiler.new(str)
    src = "def match(node0#{compiler.emit_trailing_params});" \
          "#{compiler.emit_method_code}end"
    instance_eval(src)
  end
end
