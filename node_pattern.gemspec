
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "node_pattern/version"

Gem::Specification.new do |spec|
  spec.name          = "node_pattern"
  spec.version       = NodePattern::VERSION
  spec.authors       = ["Masataka Pocke Kuwabara"]
  spec.email         = ["kuwabara@pocke.me"]

  spec.summary       = %q{}
  spec.description   = %q{}
  spec.homepage      = "https://github.com/pocke/node_pattern"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency 'rspec', '~> 3.7'
  spec.add_development_dependency 'parser', '>= 2.4.0.2'
  spec.add_runtime_dependency 'ast', '>= 2.3.0'
end
