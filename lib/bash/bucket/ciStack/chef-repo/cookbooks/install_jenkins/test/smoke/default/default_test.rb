#md+
## # encoding: utf-8

# Inspec test for recipe install_jenkins::default

# To run the whole cycle from beginning to end do the following:
# - kitchen destroy
# - kitchen create
# - kitchen converge
# - kitchen verify
#
# The Inspec reference, with examples and extensive documentation, can be
# found at http://inspec.io/docs/reference/resources/

# -  The following test verify that packages have been installed successfully.
describe package('jenkins') do
  it { should be_installed }
end

describe package('postgresql90-server') do
  it { should be_installed }
end

describe package('postgresql90') do
  it { should be_installed }
end

describe package('postgresql90-libs') do
  it { should be_installed }
end

describe package('proj') do
  it { should be_installed }
end

describe package('jq') do
  it { should be_installed }
end

describe package('postgis90') do
  it { should be_installed }
end

describe package('subversion') do
  it { should be_installed }
end
