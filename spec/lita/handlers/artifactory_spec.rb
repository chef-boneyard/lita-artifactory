require "spec_helper"

class FakeShellout
  def initialize
    @commands = []
    @times_called = 0
    @stderr = ""
  end

  attr_accessor :commands
  attr_accessor :stderr
  attr_reader :times_called
  attr_reader :stdout

  def error!
    raise Mixlib::ShellOut::ShellCommandFailed.new unless stderr.empty?
  end

  def run_command
    @times_called += 1
    if commands.last.start_with?("gem fetch")
      File.open("gem#{@times_called}.gem", "w") {}
    end
  end
end

shared_examples "an authorization failure" do
  it "includes user name in the failure message" do
    send_command("#{command} angrychef 12.0.0")
    expect(replies.first).to include(user.name)
  end

  it "includes restricted group name in the failure message" do
    send_command("#{command} angrychef 12.0.0")
    expect(replies.first).to include(user_group.to_s)
  end

  it "includes command in the failure message" do
    send_command("#{command} angrychef 12.0.0")
    expect(replies.first).to include(command)
  end
end

describe Lita::Handlers::Artifactory, lita_handler: true do
  let(:endpoint) { "http://artifactory.chef.fake" }
  let(:client) { double("Artifactory::Client") }
  let(:user_group) { :artifactory_promoters }
  let(:valid_user) { true }

  before do
    allow(subject).to receive(:client).and_return(client)
    allow(client).to receive(:endpoint).and_return(endpoint)
    # We have to explicitly call this now, see https://github.com/litaio/lita/issues/142
    allow(described_class).to receive(:new).and_return(subject)
    allow_any_instance_of(Lita::Authorization).to receive(:user_in_group?).with(anything, user_group).and_return(valid_user)
    Lita.config.handlers.artifactory.endpoint = endpoint
  end

  it { is_expected.to route_command("artifactory repositories").to(:repos) }
  it { is_expected.to route_command("artifactory promote thing 12.0.0 from here to there").with_authorization_for(user_group).to(:promote) }
  it { is_expected.to route_command("artifactory gem push thing 12.0.0").with_authorization_for(user_group).to(:push) }

  describe '#artifactory promote' do
    let(:command) { "artifactory promote" }

    before do
      allow(client).to receive(:get).with("/api/build/angrychef/12.0.0").and_return(
        "uri" => "http://artifactory.chef.fake/api/build/angrychef/12.0.0",
        "buildInfo" => {
          "name" => "angrychef",
          "number" => "12.0.0",
          "modules" => [
            {
              "id" => "com.getchef:angrychef:12.0.0",
              "artifacts" => [
                {
                  "type" => "deb",
                  "sha1" => "a0556384539dfdbc8b3097427a3c1050cfb758b0",
                  "md5" => "a66b798c29c946975dcdc8ff0a196f88",
                  "name" => "angrychef_12.0.0-1_amd64.deb",
                },
              ],
            },
          ],
        }
      )
      allow(client).to receive(:get).with("/api/search/checksum", md5: "a66b798c29c946975dcdc8ff0a196f88").and_return(
        {
          "results" => [
            {
              "uri" => "http://artifactory.chef.fake/api/storage/omnibus-current-local/com/getchef/angrychef/12.0.0/ubuntu/14.04/angrychef_12.0.0-1_amd64.deb",
            },
          ],
        }
      )
      allow(client).to receive(:get).with("/api/storage/omnibus-current-local/com/getchef/angrychef/12.0.0/ubuntu/14.04/angrychef_12.0.0-1_amd64.deb").and_return(
        {
          "repo" => "omnibus-current-local",
        }
      )

      allow(client).to receive(:post).with("/api/plugins/build/promote/stable/angrychef/12.0.0?params=comment=Promoted%20using%20the%20lita-artifactory%20plugin.%20ChatOps%20FTW!%7Cuser=Test%20User%20(1%20/%20Test%20User)", any_args).and_return("messages" => [])
    end

    it "promotes an artifact" do
      send_command("#{command} angrychef 12.0.0")

      success_response = <<-EOH
:metal: :ice_cream: *angrychef* *12.0.0* has been successfully promoted to the *stable* channel!

You can view the promoted artifacts at:
http://artifactory.chef.fake/webapp/#/artifacts/browse/tree/General/omnibus-stable-local/com/getchef/angrychef/12.0.0
      EOH
      expect(replies.first).to eq(success_response)
    end

    context "the promotion fails" do
      let(:error_message) { "Build angrychef/12.0.0 was not found, canceling promotion" }

      before do
        expect(client).to receive(:post).with(any_args).and_raise(::Artifactory::Error::HTTPError.new("status" => 500, "message" => error_message))
      end

      it "prints a failure message" do
        send_command("#{command} angrychef 12.0.0")

        error_response = <<-EOH
:scream: :skull: There was an error promoting *angrychef* *12.0.0* to the *stable* channel!

Full error message from http://artifactory.chef.fake:

```The Artifactory server responded with an HTTP Error 500: `#{error_message}'```
        EOH
        expect(replies.first).to eq(error_response)
      end
    end

    context "the user provides an invalid project or version" do
      before do
        allow(client).to receive(:get).with("/api/build/poop/33").and_raise(Artifactory::Error::HTTPError.new("status" => 404, "message" => "No build was found for build name: poop, build number: 33"))
      end

      it "prints a nice message" do
        send_command("#{command} poop 33")

        success_response = <<-EOH
:hankey: I couldn't locate a build for *poop* *33*.

Please verify *poop* is a valid project name and *33* is a valid version number.
        EOH
        expect(replies.first).to eq(success_response)
      end
    end

    context "the promoting user data is over 66 characters long" do
      let(:user) { Lita::User.create("Uxxxxxxxx", name: "Some User With A Really Long Name", mention_name: "someuserwithareallylongname") }

      it "truncates the user data to 66 characters" do
        expect(client).to receive(:post).with(%r{(.*)?user=Some%20User%20With%20A%20Really%20Long%20Name%20\(Uxxxxxxxx%20\/%20someuserwithareal(.*)?}, any_args)

        send_command("#{command} angrychef 12.0.0")
      end
    end

    context "the artifacts do not exist in the current channel" do
      before do
        allow(client).to receive(:get).with("/api/storage/omnibus-current-local/com/getchef/angrychef/12.0.0/ubuntu/14.04/angrychef_12.0.0-1_amd64.deb").and_return(
          {
            "repo" => "omnibus-unstable-local",
          }
        )
      end

      it "prints a nice message" do
        send_command("#{command} angrychef 12.0.0")

        success_response = <<-EOH
:hankey: *angrychef* *12.0.0* does not exist in the _current_ channel.

The *angrychef* *12.0.0* build was not promoted to _current_ from _unstable_ because it did not pass the required testing gates in its pipeline.
        EOH
        expect(replies.first).to eq(success_response)
      end
    end

    context "user is not in restricted group" do
      let(:valid_user) { false }

      it_behaves_like "an authorization failure"
    end
  end

  describe '#artifactory repositories' do
    let(:artifact1) { double("Artifactory::Resource::Artifact", key: "repo1") }
    let(:artifact2) { double("Artifactory::Resource::Artifact", key: "repo2") }

    before do
      allow(subject).to receive(:all_repos).and_return([artifact1, artifact2])
    end

    it "returns a comma-separeted list of repo names" do
      send_command("artifactory repositories")
      expect(replies.last).to eq("Artifact repositories: repo1, repo2")
    end
  end

  describe '#artifactory gem push' do
    let(:gem_name)    { "my_gem" }
    let(:gem_version) { "1.2.3" }
    let(:shellout)    { FakeShellout.new }
    let(:command)     { "artifactory gem push" }

    before do
      allow(Mixlib::ShellOut).to receive(:new) do |cmd|
        shellout.commands << cmd
      end.and_return(shellout)
    end

    it "fetches ruby platform" do
      send_command("#{command} #{gem_name} #{gem_version}")
      expect(shellout.commands).to include "gem fetch #{gem_name} --version #{gem_version} --platform ruby --clear-sources --source #{endpoint}/api/gems/gems-local/"
    end

    it "fetches mingw platform" do
      send_command("#{command} #{gem_name} #{gem_version}")
      expect(shellout.commands).to include "gem fetch #{gem_name} --version #{gem_version} --platform universal-mingw32 --clear-sources --source #{endpoint}/api/gems/gems-local/"
    end

    it "pushes both gems to rubygems" do
      send_command("#{command} #{gem_name} #{gem_version}")
      expect(shellout.commands).to include "gem push gem1.gem --key chef_rubygems_api_key"
      expect(shellout.commands).to include "gem push gem2.gem --key chef_rubygems_api_key"
    end

    it "pushes ONLY both gems to rubygems" do
      send_command("#{command} #{gem_name} #{gem_version}")
      expect(shellout.times_called).to eq 4
    end

    context "fail to fetch a gem" do
      before do
        shellout.stderr = "there was an error"
      end

      it "does not push anything to rubygems" do
        send_command("#{command} #{gem_name} #{gem_version}")
        expect(shellout.commands).not_to include "gem push gem.gem --key chef_rubygems_api_key"
      end
    end

    context "user is not in restricted group" do
      let(:valid_user) { false }

      it_behaves_like "an authorization failure"
    end
  end
end
