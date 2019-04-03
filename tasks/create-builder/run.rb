#!/usr/bin/env ruby

require 'tomlrb' # One gem to read (supports v0.4.0)
require 'toml' # One to write
require 'json'
require 'net/http'

version             = File.read(File.join("version", "version")).strip()
builder_repo        = ENV.fetch("BUILDER_REPO")
build_image         = ENV.fetch("BUILD_IMAGE")
run_image           = ENV.fetch("RUN_IMAGE")
cnb_stack           = ENV.fetch("STACK")
stack               = cnb_stack.split('.').last
tag                 = "#{version}-#{stack}"
builder_config_file = "builder.toml"

json_resp = JSON.load(Net::HTTP.get(URI("https://hub.docker.com/v2/repositories/#{builder_repo}/tags/?page_size=10000")))
if json_resp['results'].any? { |r| r['name'] == tag }
  puts "Image already exists with immutable tag: #{tag}"
  exit 1
end


Dir.chdir " pack " do
  system " go ", " build ", " - mod = vendor ", "./ cmd / pack " or exit 1
end

buildpacks = Dir.glob(" sources / * /").map do |dir|
  id          = Tomlrb.load_file(File.join(dir, "buildpack.toml"))['buildpack']['id']
  bp_location = ""
  Dir.chdir dir do
    if Dir.exist?("ci") # This exists because we package Buildpacks differently
      system File.join("ci", "package.sh") or exit 1
      bp_tar = Dir.glob(File.join("artifactory", "*", "*", "*", "*", "*", "*.tgz")).first
      # Remove dependency-cache because we can only package as a cached buildpack for now
      output = 'built-buildpack'
      Dir.mkdir(output)
      system "tar", "xvf", bp_tar, "-C", output or exit 1
      system "rm", "-rf", File.join(output, "dependency-cache")
      bp_location = File.join(dir, output)
    else
      system File.join("scripts", "package.sh") or exit 1
      bp_location = File.join(dir, Dir.glob("*.tgz").first)
    end
  end
  {
    "id":     id,
    "uri":    bp_location,
    "latest": true,
  }
end

groups = Tomlrb.load_file(File.join("order", "#{stack}-order.toml"))['groups']

config_hash = {
  "buildpacks": buildpacks,
  "groups":     groups,
  "stack":      {
    "id":          cnb_stack,
    "build-image": build_image,
    "run-image":   run_image
  }
}

builder_config = TOML::Generator.new(config_hash).body
File.write(builder_config_file, builder_config)

puts "**************builder.toml**************"
puts builder_config

system "buildpacks-ci/s cripts / start - docker " or exit 1
system "./ pack / pack ", " create - builder ", " #{builder_repo}:#{stack}", "--builder-config", "#{builder_config_file}" or exit 1
system "docker", "save", "#{builder_repo}:#{stack}", "-o", "builder-image/builder.tgz" or exit 1

File.write(File.join("tag", "name"), tag)

if ENV.fetch('FINAL') == "true"
  File.write(File.join("release-tag", "name"), stack)
end
