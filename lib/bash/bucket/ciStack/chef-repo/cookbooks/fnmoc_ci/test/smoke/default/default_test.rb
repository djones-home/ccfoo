# # encoding: utf-8

# Inspec test for recipe install_jenkins::default

# The Inspec reference, with examples and extensive documentation, can be
# found at http://inspec.io/docs/reference/resources/


describe package('rpm-build') do
  it { should be_installed }
end

describe package('subversion') do
  it { should be_installed }
end
