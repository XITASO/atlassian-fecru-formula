require "serverspec"

set :backend, :exec

describe service("atlassian-fecru") do
  it { should be_enabled }
  it { should be_running }
end

describe port("8060") do
  it { should be_listening }
end

describe command('curl -L localhost:8060') do
  its(:stdout) { should contain('Welcome to the Fisheye setup') }
end
