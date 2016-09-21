module Lita
  module Handlers
    class Artifactory < Handler
      config :username, required: true
      config :password, required: true
      config :endpoint, required: true
      config :base_path, default: "com/getchef"
      config :ssl_pem_file, default: nil
      config :ssl_verify, default: nil
      config :proxy_username, default: nil
      config :proxy_password, default: nil
      config :proxy_address, default: nil
      config :proxy_port, default: nil

      GEM_REGEX         = /[\w\-\.\+\_]+/
      PROJECT_REGEX     = /[\w\-\.\+\_]+/
      VERSION_REGEX     = /[\w\-\.\+\_]+/
      PROMOTION_CHANNEL = "stable"

      route(
        /^artifact(?:ory)?\s+promote\s+#{PROJECT_REGEX.source}\s+#{VERSION_REGEX.source}/i,
        :promote,
        command: true,
        restrict_to: [:artifactory_promoters],
        help: {
              "artifactory promote" => "promote <artifact> <version>",
              }
            )

      route(
        /^artifact(?:ory)?\s+repos(?:itories)?/i,
        :repos,
        command: true,
        help: {
              "artifactory repos" => "list artifact repositories",
              }
            )

      route(
        /^artifact(?:ory)?\s+gem\s+push\s+#{GEM_REGEX.source}\s+#{VERSION_REGEX.source}/i,
        :push,
        command: true,
        restrict_to: [:artifactory_promoters],
        help: {
              "artifactory gem push" => "push <gem> <version>",
              }
            )

      on :route_authorization_failed, :warn_authorization_failure

      def warn_authorization_failure(payload)
        robot.send_message(
          payload[:message].source,
          [
            payload[:message].user.name,
            ": You must be a member of one of these groups:\n\t",
            payload[:route].required_groups,
            "\nbefore calling '#{payload[:message].body}'.",
            "\nPlease ask #eng-services-support to add you.",
          ].join
        )
      end

      def promote(response)
        project       = response.args[1]
        version       = response.args[2]
        artifact_path = File.join(config.base_path, project, version)
        user          = response.user

        promotion_options = {
          comment: "Promoted using the lita-artifactory plugin. ChatOps FTW!",
          # user is limited to 64 characters
          user: "#{user.name} (#{user.id} / #{user.mention_name})"[0..63],
        }

        # attempt to locate the build
        build = ::Artifactory::Resource::Build.find(project, version, client: client)

        if build.nil?
          reply_msg = <<-EOH.gsub(/^ {12}/, "")
            :hankey: I couldn't locate a build for *#{project}* *#{version}*.

            Please verify *#{project}* is a valid project name and *#{version}* is a valid version number.
          EOH
          response.reply reply_msg

          return
        end

        # Validate the artifacts all exist in `omnibus-current-local`
        unless repos_for(build).all? { |r| r == "omnibus-current-local" }
          reply_msg = <<-EOH.gsub(/^ {12}/, "")
            :hankey: *#{project}* *#{version}* does not exist in the _current_ channel.

            The *#{project}* *#{version}* build was not promoted to _current_ from _unstable_ because it did not pass the required testing gates in its pipeline.
          EOH
          response.reply reply_msg

          return
        end

        # Artifactory expects parameters in the form:
        #
        #   params=<PARAM1_NAME>=<PARAM1_VALUE>|<PARAM2_NAME>=<PARAM2_VALUE>
        #
        params = promotion_options.map { |k, v| "#{k}=#{v}" }.join("|")
        path   = ["/api/plugins/build/promote", PROMOTION_CHANNEL, build.name, build.number].join("/")
        path   = [path, "params=#{params}"].compact.join("?")

        begin
          client.post(URI.encode(path), nil)

          reply_msg = <<-EOH.gsub(/^ {12}/, "")
            :metal: :ice_cream: *#{project}* *#{version}* has been successfully promoted to the *#{PROMOTION_CHANNEL}* channel!

            You can view the promoted artifacts at:
            #{config.endpoint}/webapp/#/artifacts/browse/tree/General/omnibus-#{PROMOTION_CHANNEL}-local/#{artifact_path}
          EOH
        rescue ::Artifactory::Error::HTTPError => e
          reply_msg = <<-EOH.gsub(/^ {12}/, "")
            :scream: :skull: There was an error promoting *#{project}* *#{version}* to the *#{PROMOTION_CHANNEL}* channel!

            Full error message from #{config.endpoint}:

            ```#{e.message}```
          EOH
        end

        response.reply reply_msg
      end

      def push(response)
        ruby_gem      = response.args[2]
        version       = response.args[3]
        human_name    = "#{ruby_gem} gem version #{version}"
        gem_source    = "#{config.endpoint}/api/gems/gems-local/"
        missing_gem   = false

        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            %w{ruby universal-mingw32}.each do |platform|
              cmd = Mixlib::ShellOut.new(fetch_command_for_platform(platform, ruby_gem, version, gem_source))
              cmd.run_command
              unless cmd.stderr.empty?
                response.reply(":warning: :warning: There were errors retrieving the #{human_name} from #{gem_source}! :warning: :warning:\n#{cmd.stderr}")
                missing_gem = true
                break
              end
              response.reply cmd.stdout
            end

            break if missing_gem

            Dir.glob("*.gem") do |gem_file|
              cmd = Mixlib::ShellOut.new("gem push #{gem_file} --key chef_rubygems_api_key")
              cmd.run_command
              begin
                cmd.error!
                response.reply(":rockon: Succesfully pushed #{gem_file} to rubygems! :rockon:")
              rescue Mixlib::ShellOut::ShellCommandFailed => e
                response.reply(":warning: :warning: Failed pushing #{gem_file} to rubygems! :warning: :warning:\n#{e}")
              end
            end
          end
        end
      end

      def repos(response)
        response.reply "Artifact repositories: #{all_repos.collect(&:key).sort.join(', ')}"
      end

      private

      def client
        @client ||= ::Artifactory::Client.new(
          endpoint:       config.endpoint,
          username:       config.username,
          password:       config.password,
          ssl_pem_file:   config.ssl_pem_file,
          ssl_verify:     config.ssl_verify,
          proxy_username: config.proxy_username,
          proxy_password: config.proxy_password,
          proxy_address:  config.proxy_address,
          proxy_port:     config.proxy_port
        )
      end

      def all_repos
        ::Artifactory::Resource::Repository.all(client: client)
      end

      def repos_for(build)
        repos = []

        # Multiple artifact paths may be the same underlying artifact,
        # this is Artifactory's de-duping in action.
        uniq_md5s = build.modules.first["artifacts"].map { |a| a["md5"] }.uniq

        uniq_md5s.each do |md5|
          ::Artifactory::Resource::Artifact.checksum_search(
            md5: md5,
            client: client
          ).each do |a|
            repos << a.repo
          end
        end

        repos.uniq
      end

      def fetch_command_for_platform(platform, gem_name, version, source)
        [
          "gem fetch",
          gem_name,
          "--version",
          version,
          "--platform",
          platform,
          "--clear-sources",
          "--source",
          source,
        ].join(" ")
      end
    end

    Lita.register_handler(Artifactory)
  end
end
