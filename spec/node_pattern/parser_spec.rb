describe NodePattern::Parser do
  shared_examples :parsable do |pattern|
    it 'is parsable' do
      parser = NodePattern::Parser.new(pattern)
      parser.raise_error unless parser.parse
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
    end
  end

  include_examples :parsable, '(send)'
  include_examples :parsable, '( foo )'
  include_examples :parsable, <<-PATTERN
    (
      bar
    )
  PATTERN
  include_examples :xparsable, '(send foo)'
end
