# lita-artifactory
[![Build Status](https://travis-ci.org/chef/lita-artifactory.svg)](https://travis-ci.org/chef/lita-artifactory)

lita plugin for artifactory.  Specific to Chef Software, Inc.'s omnibus repositories.

## Installation

Add lita-artifactory to your Lita instance's Gemfile:

``` ruby
gem "lita-artifactory"
```


## Configuration

The following parameters are required and MUST be set in your lita config:

````
config.handlers.artifactory.username     # username for making artifactory requests
config.handlers.artifactory.password     # password for making artifactory requests
config.handlers.artifactory.endpoint     # base URL for artifactory requests
````

The following parameters are optional:

````
# Base path of the artifactory repo (defaults to 'com/getchef')
config.handlers.artifactory.base_path

# SSL (default to nil)
config.handlers.artifactory.ssl_pem_file
config.handlers.artifactory.ssl_verify

# Proxy (default to nil)
config.handlers.artifactory.proxy_username
config.handlers.artifactory.proxy_password
config.handlers.artifactory.proxy_address
config.handlers.artifactory.proxy_port
````
## Usage

````
artifactory promote <artifact> <version>

artifactory gem push <gem_name> <version>

artifactory repos # list all the artifact repositories under the base path
````

## Consuming the `artifactory_artifact_promoted` event
When an artifact is successfully promoted from the *current* to *stable* channel,
a `artifactory_artifact_promoted` event is published. If you wish to trigger
behavior in your Lita plugin when certain projects are promoted, you can
write an [event route](https://docs.lita.io/plugin-authoring/handlers/#event-routes)
that will listen for that event.

## Local Testing With the Shell Adapter
### Install redis
````
`brew install redis`             # install a redis server
`redis-server /usr/local/etc/redis.conf`  # start a non-daemonized redis server listening on port 6379
````

### Set up a skeleton lita project
Install the `lita` gem however you like to install your gems and use it to create a new project.  I create a minimal Gemfile and use bundler:
````
bundle install lita   # install the lita gem

bundle exec lita new  # create a new lita project with the default shell adapter
````
This will create a subdirectory called `lita` in the current directory; `lita` contains skeleton files for a `lita` project.

### Load the lita-artifactory gem
Point the Gemfile in `lita` to the `lita-artifactory` plugin.

````
source "https://rubygems.org"

gem "lita"
gem 'lita-artifactory', path: '/Users/yvonnelam/src/lita-projects/lita-artifactory'
````

Fill out `lita_config.rb` to use your `redis` installation and set the config parameters that `lita-artifactory` needs.

### Run the plugin using the shell adapter
In the `lita` directory, install the necessary gems and run `lita`:

````
sealam01:lita-projects yvonnelam$ cd lita
sealam01:lita yvonnelam$ bundle install
sealam01:lita yvonnelam$ bundle exec lita

sealam01:lita yvonnelam$ bundle exec lita
fatal: Not a git repository (or any of the parent directories): .git
[2014-12-16 00:07:56 UTC] WARN: Struct-style access of config.redis is deprecated and will be removed in Lita 5.0. config.redis is now a hash.
Type "exit" or "quit" to end the session.
Lita >
````

To talk to the shell adapter, type

`@lita <your plugin command>`

e.g.
````
Lita > @lita artifactory repos
Artifact repositories:  omnibus-current-local, omnibus-stable-local, libs-release-local, libs-snapshot-local, repo
Lita > @lita artifact promote angrychef 12.0.0-alpha.1+20140830080511.git.87.d404a1a
Moving omnibus-current-local:com/getchef/angrychef/12.0.0-alpha.1+20140830080511.git.87.d404a1a to omnibus-stable-local:com/getchef/angrychef/12.0.0-alpha.1 20140830080511.git.87.d404a1a completed successfully
````

## License
Author:  Yvonne Lam <yvonne@getchef.com>

````
Copyright 2014 Chef Software, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
````
