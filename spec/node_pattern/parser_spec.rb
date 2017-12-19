describe NodePattern::Parser do
  extend AST::Sexp

  shared_examples :parsable do |pattern, expected|
    it "#{pattern.gsub("\n", '\n')} is parsable" do
      parser = NodePattern::Parser.new(pattern)
      parser.raise_error unless parser.parse
      expect(parser.ast).to eq expected
    end
  end

  shared_examples :nonparsable do |pattern|
    it 'is parsable' do
      parser = NodePattern::Parser.new(pattern)
      raise 'It can parse!' if parser.parse
    end
  end

  shared_examples :xparsable do |pattern, expected|
    xcontext do
      include_examples :parsable, pattern, expected
    end
  end

  # node
  include_examples :xparsable, 'send', s(:node, 'send', s(:rest))
  include_examples :parsable, '(send)', s(:node, 'send')
  include_examples :parsable, '( foo )', s(:node, 'foo')
  include_examples :parsable, <<-PATTERN, s(:node, 'bar')
    (
      bar
    )
  PATTERN
  include_examples :parsable, '(int _)',
                              s(:node, 'int', s(:any))
  include_examples :parsable, '(send _ _ _ _)',
                              s(:node, 'send', s(:any), s(:any), s(:any), s(:any))
  include_examples :parsable, '(send (int) _)',
                              s(:node, 'send', s(:node, 'int'), s(:any))

  # any
  include_examples :parsable, '_', s(:any)

  # literal
  include_examples :parsable, '(send _ :do_something)',
                              s(:node, 'send', s(:any), s(:literal, :do_something))
  include_examples :xparsable, '(send _ :$foo)',
                               s(:node, 'send', s(:any), s(:literal, :$foo))
  include_examples :xparsable, '(send _ :+)',
                               s(:node, 'send', s(:any), s(:literal, :+))

  include_examples :parsable, '(int 1)',
                              s(:node, 'int', s(:literal, 1))
  include_examples :parsable, '(int -1)',
                              s(:node, 'int', s(:literal, -1))
  include_examples :parsable, '(int -123)',
                              s(:node, 'int', s(:literal, -123))
  include_examples :parsable, '(int 42)',
                              s(:node, 'int', s(:literal, 42))

  include_examples :parsable, '(float 1.0)',
                              s(:node, 'float', s(:literal, 1.0))
  include_examples :parsable, '(float -2.0)',
                              s(:node, 'float', s(:literal, -2.0))
  include_examples :parsable, '(float -123.467)',
                              s(:node, 'float', s(:literal, -123.467))
  include_examples :parsable, '(float 42.42)',
                              s(:node, 'float', s(:literal, 42.42))

  include_examples :parsable, '1', s(:literal, 1)

  # or
  include_examples :parsable, '{1 2}', s(:or, s(:literal, 1), s(:literal, 2))
  include_examples :parsable, '(send _ {:foo :bar})',
                              s(:node, 'send', s(:any), s(:or, s(:literal, :foo), s(:literal, :bar)))
  node = s(:or,
           s(:node, 'send', s(:any), s(:literal, :foo)),
           s(:node, 'send', s(:any), s(:literal, :bar))
          )
  include_examples :parsable, <<-PATTERN, node
    {
      (send _ :foo)
      (send _ :bar)
    }
  PATTERN

  # predicate
  include_examples :parsable, '(send nil? _)', s(:node, 'send', s(:predicate, :nil?), s(:any))

  # not
  include_examples :parsable, '(send !nil? _)', s(:node, 'send', s(:not, s(:predicate, :nil?)), s(:any))
end
