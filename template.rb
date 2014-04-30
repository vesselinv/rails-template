insert_into_file('Gemfile', "ruby '#{RUBY_VERSION}'\n", before: /^ *gem 'rails'/, force: false)

case ask("Choose Database:", limited_to: %w[sqlite mysql pg])
when "mysql"
  gem "mysql2"
when "pg"
  gem "pg"
when "sqlite"
end

case ask("Choose Template Engine:", limited_to: %w[erb haml slim])
when "haml"
  gem "haml-rails"
when "slim"
  gem 'slim-rails'
when "erb"
end

# Clean up all comments from Gemfile
gsub_file 'Gemfile', /#.*\n/, ''
gsub_file 'Gemfile', /gem 'sass-rails'.*/, ''

gem 'bcrypt'
gem 'unicorn'
gem 'sass-rails'
gem 'compass-rails'
gem 'sprockets'
gem 'sprockets-sass'

gem_group :development do
  gem 'guard'
  gem 'guard-rails'
  gem 'guard-livereload'
  gem 'guard-bundler'
  gem 'guard-rspec'
  gem 'guard-brakeman'
  gem 'better_errors'
  gem 'binding_of_caller'
  gem 'meta_request'
  gem 'awesome_print'
  gem 'bullet'
  gem 'debugger'
  gem 'spring'
  gem 'spring-commands-rspec'
end

gem_group :test do
  gem 'faker'
  gem 'capybara'
  gem 'rspec_candy'
  gem 'database_cleaner'
  gem 'fakeweb'
  gem 'delorean'
  gem 'rspec-rails'
  gem 'mocha'
  gem 'shoulda-matchers'
  gem 'factory_girl_rails'
  gem 'fuubar'
  gem 'simplecov', require: false
end

gem_group :production do
  gem 'rails_12factor'
end

# Remove blank lines
gsub_file('Gemfile', /^[ \t]*$\r?\n/, '')

initializer 'generators.rb', <<-RUBY
Rails.application.config.generators do |g|
  g.test_framework :rspec,
    fixtures:         true,
    view_specs:       false,
    helper_specs:     false,
    routing_specs:    false,
    controller_specs: true,
    request_specs:    true
  g.fixture_replacement :factory_girl, dir: "spec/factories"
end
RUBY

insert_into_file('config/environments/development.rb',
"
  # Bullet
  config.after_initialize do
    Bullet.enable         = true
    Bullet.alert          = false
    Bullet.bullet_logger  = true
    Bullet.console        = true
    Bullet.rails_logger   = true
    Bullet.add_footer     = true
  end
", before: /^end/, force: false)

# Use Procfile for foreman
run "echo 'web: bundle exec rails server -p $PORT' >> Procfile"
run "echo PORT=3000 >> .env"
run "echo '.env' >> .gitignore"
# We need this with foreman to see log output immediately
run "echo 'STDOUT.sync = true' >> config/environments/development.rb"

# Bundle install first
run 'bundle install'

# Install rspec
generate 'rspec:install'

# Add Simple cov, factory girl, awesome print and db cleaner to spec helper
insert_into_file('spec/spec_helper.rb', "
require 'simplecov'
require 'factory_girl'
require 'factory_girl_rails'
require 'awesome_print'
SimpleCov.start 'rails' do
  add_filter '/config/'

  add_group 'Controllers',  'app/controllers'
  add_group 'Models',       'app/models'
  add_group 'Helpers',      'app/helpers'
  add_group 'Mailers',      'app/mailers'
  add_group 'Libraries',    'lib'
end
", after: /^require 'rspec\/autorun'/)

insert_into_file('spec/spec_helper.rb', "
  config.before(:all) do
    DeferredGarbageCollection.start
  end

  config.after(:all) do
    DeferredGarbageCollection.reconsider
  end

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.start
  end

  config.before(:each, js: true) do
    DatabaseCleaner.strategy = :truncation
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end
", after: /config\.order = "random"/)

# Remove test dir
run "rm -rf test/"

# Initialize guard plugins
run "bundle exec guard init bundler rails livereload rspec brakeman"

# generate binstubs for spring
run "bundle exec spring binstub --all"

# Add Unicorn config for Heroku
file 'config/unicorn.rb', <<-RUBY
worker_processes Integer(ENV["WEB_CONCURRENCY"] || 3)
timeout 15
preload_app true

before_fork do |server, worker|
  Signal.trap 'TERM' do
    puts 'Unicorn master intercepting TERM and sending myself QUIT instead'
    Process.kill 'QUIT', Process.pid
  end

  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.connection.disconnect!
end

after_fork do |server, worker|
  Signal.trap 'TERM' do
    puts 'Unicorn worker intercepting TERM and doing nothing. Wait for master to send QUIT'
  end

  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.establish_connection
end
RUBY

# Common ignore files
run "cat << EOF >> .gitignore
/.bundle
/db/*.sqlite3
/db/*.sqlite3-journal
/log/*.log
/tmp
database.yml
.env
doc/
*.swp
*~
.project
.idea
.secret
.DS_Store
EOF"

# Git: Initialize
git :init
git add: "."
git commit: %Q{ -m 'Initial commit' }

if yes?("Initialize GitHub repository?")
  git_uri = `git config remote.origin.url`.strip
  unless git_uri.size == 0
    say "Repository already exists:"
    say "#{git_uri}"
  else
    username = ask "What is your GitHub username?"
    run "curl -u #{username} -d '{\"name\":\"#{app_name}\"}' https://api.github.com/user/repos"
    git remote: %Q{ add origin git@github.com:#{username}/#{app_name}.git }
    git push: %Q{ origin master }
  end
end
