module Lita
  module Handlers
    class Artifactory < Handler
      config :username, required: true
      config :password, required: true
      config :endpoint, required: true
      config :base_path, default: 'com/getchef'
      config :ssl_pem_file, default: nil
      config :ssl_verify, default: nil
      config :proxy_username, default: nil
      config :proxy_password, default: nil
      config :proxy_address, default: nil
      config :proxy_port, default: nil

      PROJECT_REGEX     = /[\w\-\.\+\_]+/
      VERSION_REGEX     = /[\w\-\.\+\_]+/
      PROMOTION_CHANNEL = 'stable'

      route(/^artifact(?:ory)?\s+promote\s+#{PROJECT_REGEX.source}\s+#{VERSION_REGEX.source}/i, :promote, command: true, help: {
              'artifactory promote' => 'promote <artifact> <version>',
            })

      route(/^artifact(?:ory)?\s+repos(?:itories)?/i, :repos, command: true, help: {
              'artifactory repos' => 'list artifact repositories',
            })

      def promote(response)
        project       = response.args[1]
        version       = response.args[2]
        artifact_path = File.join(config.base_path, project, version)
        user          = response.user

        promotion_options = {
          comment: 'Promoted using the lita-artifactory plugin. ChatOps FTW!',
          # user is limited to 64 characters
          user: "#{user.name} (#{user.id} / #{user.mention_name})"[0..63],
        }

        # attempt to locate the build
        build = ::Artifactory::Resource::Build.find(project, version, client: client)

        if build.nil?
          reply_msg = <<-EOH.gsub(/^ {12}/, '')
            :hankey: I couldn't locate a build for *#{project}* *#{version}*.

            Please verify *#{project}* is a valid project name and *#{version}* is a valid version number.
          EOH
          response.reply reply_msg

          return
        end

        # Artifactory expects parameters in the form:
        #
        #   params=<PARAM1_NAME>=<PARAM1_VALUE>|<PARAM2_NAME>=<PARAM2_VALUE>
        #
        params = promotion_options.map { |k, v| "#{k}=#{v}" }.join('|')
        path   = ['/api/plugins/build/promote', PROMOTION_CHANNEL, build.name, build.number].join('/')
        path   = [path, "params=#{params}"].compact.join('?')

        begin
          client.post(URI.encode(path), nil)

          reply_msg = <<-EOH.gsub(/^ {12}/, '')
            :metal: :ice_cream: *#{project}* *#{version}* has been successfully promoted to the *#{PROMOTION_CHANNEL}* channel!

            You can view the promoted artifacts at:
            #{config.endpoint}/webapp/browserepo.html?pathId=omnibus-#{PROMOTION_CHANNEL}-local:#{artifact_path}
          EOH
        rescue ::Artifactory::Error::HTTPError => e
          reply_msg = <<-EOH.gsub(/^ {12}/, '')
            :scream: :skull: There was an error promoting *#{project}* *#{version}* to the *#{PROMOTION_CHANNEL}* channel!

            Full error message from #{config.endpoint}:

            ```#{e.message}```
          EOH
        end

        response.reply reply_msg
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
          proxy_port:     config.proxy_port,
        )
      end

      def all_repos
        ::Artifactory::Resource::Repository.all(client: client)
      end
    end

    Lita.register_handler(Artifactory)
  end
end
