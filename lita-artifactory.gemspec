Gem::Specification.new do |spec|
  spec.name          = "lita-artifactory"
  spec.version       = "0.0.1"
  spec.authors       = ["Yvonne Lam"]
  spec.email         = ["yvonne@opscode.com"]
  spec.description   = "lita plugin for artifactory"
  spec.summary       = "lita plugin for artifactory"
  spec.homepage      = "http://example.com"
  spec.license       = "MIT"
  spec.metadata      = { "lita_plugin_type" => "handler" }

  spec.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "lita", ">= 4.0"
  spec.add_dependency "artifactory", ">= 2.3.0"
  spec.add_dependency "mixlib-shellout"

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "chefstyle", "~> 0.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rack-test"
  spec.add_development_dependency "rspec", ">= 3.0.0"
  spec.add_development_dependency "rubocop"
end
