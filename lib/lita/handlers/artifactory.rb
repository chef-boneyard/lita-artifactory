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

      ARTIFACT = /[\w\-\.\+\_]+/
      VERSION = /[\w\-\.\+\_]+/
      FROM_REPO = /[\w\-]+/
      TO_REPO = /[\w\-]+/

      route(/^artifact(?:ory)?\s+promote\s+#{ARTIFACT.source}\s+#{VERSION.source}\s+from\s+#{FROM_REPO.source}\s+to\s+#{TO_REPO.source}/i, :promote, command: true, help: {
              'artifactory promote' => 'promote <artifact> <version> from <from-repo> to <to-repo>',
            })

      route(/^artifact(?:ory)?\s+repos(?:itories)?/i, :repos, command: true, help: {
              'artifactory repos' => 'list artifact repositories',
            })

      def promote(response)
        project       = response.args[1]
        version       = response.args[2]
        artifact_path = File.join(config.base_path, project, version)
        repo_from     = repo_name(response.args[4])
        repo_to       = repo_name(response.args[6])
        artifact_from = File.join(repo_from, artifact_path)
        artifact_to   = File.join(repo_to, artifact_path)

        # Dry run first.
        artifactory_response = move_folder("/api/move/#{artifact_from}?to=#{artifact_to}&dry=1")

        if artifactory_response.include?('successfully')
          artifactory_response = move_folder("/api/move/#{artifact_from}?to=#{artifact_to}&dry=0")
          reply_msg = <<-EOH.gsub(/^ {12}/, '')
            *#{project}* *#{version}* has been successfully promoted to *#{repo_to}*! You can view the promoted artifacts at:
            #{config.endpoint}/webapp/browserepo.html?pathId=#{repo_to}:#{artifact_path}

            Full response message from #{config.endpoint}:

            ```#{artifactory_response}```
          EOH
          response.reply reply_msg
        else
          reply_msg = <<-EOH.gsub(/^ {12}/, '')
            There was an error promoting *#{project}* *#{version}* to *#{repo_to}*.

            Full error message from #{config.endpoint}:

            ```#{artifactory_response}```
          EOH
          response.reply reply_msg
        end
      end

      def repos(response)
        response.reply "Artifact repositories:  #{all_repos.collect(&:key).sort.join(', ')}"
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

      # Using a raw request because the artifactory-client does not directly
      # support moving a folder.
      # @TODO:  investigate raw requests further.  Params not working the way
      # I (naively) thought they would.
      def move_folder(uri)
        cmd = client.post(uri, fake: 'stuff')
        cmd['messages'][0]['message']
      end

      def repo_name(repo)
        tmp = repo
        tmp = 'omnibus-current-local' if tmp.eql?('current')
        tmp = 'omnibus-stable-local' if tmp.eql?('stable')
        tmp
      end
    end

    Lita.register_handler(Artifactory)
  end
end
