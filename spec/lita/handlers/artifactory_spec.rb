require 'spec_helper'

describe Lita::Handlers::Artifactory, lita_handler: true do
  before do
    Lita.config.handlers.artifactory.endpoint = 'http://artifactory.chef.co'
  end

  it { is_expected.to route_command('artifactory repositories').to(:repos) }
  it { is_expected.to route_command('artifactory promote thing 12.0.0 from here to there').to(:promote) }

  describe '#artifactory promote' do
    let(:client) { double('Artifactory::Client') }

    before do
      allow(subject).to receive(:client).and_return(client)
      allow(client).to receive(:get).with('/api/build/angrychef/12.0.0').and_return('uri' => 'http://artifactory.chef.co/api/build/angrychef/12.0.0', 'buildInfo' => { 'name' => 'angrychef', 'number' => '12.0.0' })
      allow(client).to receive(:post).with('/api/build/promote/angrychef/12.0.0', any_args).and_return('messages' => [])
    end

    it 'promotes an artifact' do
      send_command('artifactory promote angrychef 12.0.0')

      success_response = <<-EOH
:metal: :ice_cream: *angrychef* *12.0.0* has been successfully promoted to *omnibus-stable-local*!

You can view the promoted artifacts at:
http://artifactory.chef.co/webapp/browserepo.html?pathId=omnibus-stable-local:com/getchef/angrychef/12.0.0
      EOH
      expect(replies.first).to eq(success_response)
    end

    context 'the promotion fails' do
      before do
        allow(client).to receive(:post).with('/api/build/promote/angrychef/12.0.0', any_args).and_return('messages' => [{ 'level' => 'error', 'message' => 'Some error message.' }, { 'level' => 'error', 'message' => 'Some other error message.' }])
      end

      it 'prints a failure message' do
        send_command('artifactory promote angrychef 12.0.0')

        success_response = <<-EOH
:scream: :skull: There was an error promoting *angrychef* *12.0.0* to *omnibus-stable-local*!

Full error message from http://artifactory.chef.co:

```Some error message.
Some other error message.```
        EOH
        expect(replies.first).to eq(success_response)
      end
    end
  end

  describe '#artifactory repositories' do
    let(:client)    { double('Artifactory::Client') }
    let(:artifact1) { double('Artifactory::Resource::Artifact', key: 'repo1') }
    let(:artifact2) { double('Artifactory::Resource::Artifact', key: 'repo2') }

    before do
      allow(subject).to receive(:client).and_return(client)
      allow(subject).to receive(:all_repos).and_return([artifact1, artifact2])
    end

    it 'returns a comma-separeted list of repo names' do
      send_command('artifactory repositories')
      expect(replies.last).to eq('Artifact repositories: repo1, repo2')
    end
  end
end
