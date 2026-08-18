Gem::Specification.new do |spec|
  spec.name          = "misarreach"
  spec.version       = "1.0.0"
  spec.authors       = ["Misar AI"]
  spec.email         = ["hello@misar.io"]
  spec.summary       = "Official Ruby SDK for MisarReach — lead finder, outreach channels, CRM, autopilot"
  spec.description   = "Full-featured Ruby SDK for the MisarReach developer API (api.misar.io/reach/api). " \
                       "Covers all 12 resource groups and 84 operations, including the lead-finder SSE job stream. " \
                       "Pure Net::HTTP, no runtime dependencies."
  spec.homepage      = "https://misarreach.com/docs"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.7"

  spec.metadata = {
    "homepage_uri"    => spec.homepage,
    "documentation_uri" => "https://misarreach.com/docs/sdks/ruby",
    "source_code_uri"   => "https://github.com/Misar-AI/misarreach-sdks",
    "changelog_uri"     => "https://github.com/Misar-AI/misarreach-sdks/blob/main/sdks/ruby/CHANGELOG.md",
    "bug_tracker_uri"   => "https://github.com/Misar-AI/misarreach-sdks/issues"
  }

  spec.files         = Dir["lib/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "webmock", "~> 3.23"
  spec.add_development_dependency "simplecov", "~> 0.22"
end
