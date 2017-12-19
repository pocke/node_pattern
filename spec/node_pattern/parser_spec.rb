describe NodePattern::Parser do
  extend AST::Sexp

  shared_examples :parsable do |pattern, expected|
    it "#{pattern} is parsable" do
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

  shared_examples :xparsable do |pattern|
    xit 'is parsable' do
      parser = NodePattern::Parser.new(pattern)
      parser.raise_error unless parser.parse
      expect(parser.ast).to eq expected
    end
  end

  # node
  include_examples :parsable, '(send)', s(:node, 'send')
  include_examples :parsable, '( foo )', s(:node, 'foo')
  include_examples :parsable, <<-PATTERN, s(:node, 'bar')
    (
      bar
    )
  PATTERN
  include_examples :parsable, '(int _)',
                              s(:node, 'int', s(:any))
  include_examples :xparsable, '(send _ :do_something)',
                               s(:node, 'send', s(:any), s(:literal, :do_something))

  # any
  include_examples :parsable, '_', s(:any)
end
