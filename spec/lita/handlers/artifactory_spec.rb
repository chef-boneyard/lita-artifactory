require "spec_helper"

describe Lita::Handlers::Artifactory, lita_handler: true do
  it { is_expected.to route_command('artifactory repositories').to(:repos) }
  it { is_expected.to route_command('artifactory promote thing 12.0.0 from here to there').to(:promote) }

  describe "#artifactory promote" do
    let(:client)   { double('Artifactory::Client') }

    before do
      allow(subject).to receive(:client).and_return(client)
      allow(client).to receive(:post).with('/api/copy/omnibus-current-local/com/getchef/angrychef/12.0.0?to=omnibus-stable-local/com/getchef/angrychef/12.0.0&dry=1', {:fake=>"stuff"}).and_return({ "messages" => [ {"level"=>"INFO", "message"=>"Dry Run for copying omnibus-current-local:com/getchef/angrychef/12.0.0 to omnibus-stable-local:com/getchef/angrychef/12.0.0 completed successfully"} ] } )
      allow(client).to receive(:post).with('/api/copy/omnibus-current-local/com/getchef/angrychef/12.0.0?to=omnibus-stable-local/com/getchef/angrychef/12.0.0&dry=0', {:fake=>"stuff"}).and_return({ "messages" => [ {"level"=>"INFO", "message"=>"Copying omnibus-current-local:com/getchef/angrychef/12.0.0 to omnibus-stable-local:com/getchef/angrychef/12.0.0 completed successfully"} ] } )
    end

    it 'does a dry run' do
      send_command('artifactory promote angrychef 12.0.0 from local to stable')
      expect(replies.last).to eq('Copying omnibus-current-local:com/getchef/angrychef/12.0.0 to omnibus-stable-local:com/getchef/angrychef/12.0.0 completed successfully')
    end
  end

  describe "#artifactory repositories" do
    let(:client)   { double('Artifactory::Client') }
    let(:artifact1) { double('Artifactory::Resource::Artifact', key: 'repo1') }
    let(:artifact2) { double('Artifactory::Resource::Artifact', key: 'repo2') }

    before do
      allow(subject).to receive(:client).and_return(client)
      allow(subject).to receive(:all_repos).and_return( [artifact1, artifact2] )
    end

    it "returns a comma-separeted list of repo names" do
      send_command('artifactory repositories')
      expect(replies.last).to eq('Artifact repositories:  repo1, repo2')
    end
  end
end
