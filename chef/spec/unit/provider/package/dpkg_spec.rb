#
# Author:: Bryan McLellan (btm@loftninjas.org)
# Copyright:: Copyright (c) 2009 Bryan McLellan
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..", "spec_helper"))

describe Chef::Provider::Package::Dpkg, "load_current_resource" do
  before(:each) do
    @node = mock("Chef::Node", :null_object => true)
    @new_resource = mock("Chef::Resource::Package", 
      :null_object => true,
      :name => "wget",
      :version => nil,
      :package_name => "wget",
      :updated => nil,
      :source => "/tmp/wget_1.11.4-1ubuntu1_amd64.deb"
    )

    @provider = Chef::Provider::Package::Dpkg.new(@node, @new_resource)

    @stdin = mock("STDIN", :null_object => true)
    @stdout = mock("STDOUT", :null_object => true)
    @status = mock("Status", :exitstatus => 0)
    @stderr = mock("STDERR", :null_object => true)
    @pid = mock("PID", :null_object => true)
    @provider.stub!(:popen4).and_return(@status)

    ::File.stub!(:exists?).and_return(true)
  end
  
  it "should create a current resource with the name of the new_resource" do
    @provider.load_current_resource
    @provider.current_resource.package_name.should == "wget"
  end
  
  it "should raise an exception if a source is supplied but not found" do
    ::File.stub!(:exists?).and_return(false)
    lambda { @provider.load_current_resource }.should raise_error(Chef::Exceptions::Package)
  end

  it "should get the source package version from dpkg-deb if provided" do
    @stdout.stub!(:each).and_yield("wget\t1.11.4-1ubuntu1")
    @provider.stub!(:popen4).with("dpkg-deb -W #{@new_resource.source}").and_yield(@pid, @stdin, @stdout, @stderr).and_return(@status)
    @new_resource.should_receive(:version).with("1.11.4-1ubuntu1")
    @provider.load_current_resource
    @provider.current_resource.package_name.should == "wget"
  end
  
  it "gets the source package name from dpkg-deb correctly when the package name has `-' or `+' characters" do
    @stdout.stub!(:each).and_yield("foo-pkg++2\t1.11.4-1ubuntu1")
    @provider.stub!(:popen4).and_yield(@pid, @stdin, @stdout, @stderr).and_return(@status)
    @provider.load_current_resource
    @provider.current_resource.package_name.should == "foo-pkg++2"
  end

  it "should raise an exception if the source is not set but we are installing" do
    @new_resource = mock("Chef::Resource::Package", 
      :null_object => true,
      :name => "wget",
      :version => nil,
      :package_name => "wget",
      :updated => nil,
      :source => nil
    )
    @provider = Chef::Provider::Package::Dpkg.new(@node, @new_resource)
    lambda { @provider.load_current_resource }.should raise_error(Chef::Exceptions::Package)

  end

  it "should return the current version installed if found by dpkg" do
    @stdout.stub!(:each).and_yield("Package: wget").
                               and_yield("Status: install ok installed").
                               and_yield("Priority: important").
                               and_yield("Section: web").
                               and_yield("Installed-Size: 1944").
                               and_yield("Maintainer: Ubuntu Core developers <ubuntu-devel-discuss@lists.ubuntu.com>").
                               and_yield("Architecture: amd64").
                               and_yield("Version: 1.11.4-1ubuntu1").
                               and_yield("Config-Version: 1.11.4-1ubuntu1").
                               and_yield("Depends: libc6 (>= 2.8~20080505), libssl0.9.8 (>= 0.9.8f-5)").
                               and_yield("Conflicts: wget-ssl")
    @provider.stub!(:popen4).with("dpkg -s wget").and_yield(@pid, @stdin, @stdout, @stderr).and_return(@status)
    
    @provider.load_current_resource
    @provider.current_resource.version.should == "1.11.4-1ubuntu1"
  end
  
  it "should raise an exception if dpkg fails to run" do
    @status = mock("Status", :exitstatus => -1)
    @provider.stub!(:popen4).and_return(@status)
    lambda { @provider.load_current_resource }.should raise_error(Chef::Exceptions::Package)
  end
end

describe Chef::Provider::Package::Dpkg, "install and upgrade" do
  before(:each) do
    @node = mock("Chef::Node", :null_object => true)
    @new_resource = mock("Chef::Resource::Package", 
      :null_object => true,
      :name => "wget",
      :version => nil,
      :package_name => "wget",
      :updated => nil,
      :source => "/tmp/wget_1.11.4-1ubuntu1_amd64.deb",
      :options => nil
    )
    @provider = Chef::Provider::Package::Dpkg.new(@node, @new_resource)
  end

  it "should run dpkg -i with the package source" do
    @provider.should_receive(:run_command_with_systems_locale).with({
      :command => "dpkg -i /tmp/wget_1.11.4-1ubuntu1_amd64.deb",
      :environment => {
        "DEBIAN_FRONTEND" => "noninteractive"
      }
    })
    @provider.install_package("wget", "1.11.4-1ubuntu1")
  end

  it "should run dpkg -i with the package source and options if specified" do
    @provider.should_receive(:run_command_with_systems_locale).with({
      :command => "dpkg -i --force-yes /tmp/wget_1.11.4-1ubuntu1_amd64.deb",
      :environment => {
        "DEBIAN_FRONTEND" => "noninteractive"
      }
    })
    @new_resource.stub!(:options).and_return("--force-yes")

    @provider.install_package("wget", "1.11.4-1ubuntu1")
  end
  it "should upgrade by running install_package" do
    @provider.should_receive(:install_package).with("wget", "1.11.4-1ubuntu1")
    @provider.upgrade_package("wget", "1.11.4-1ubuntu1")
  end
end

describe Chef::Provider::Package::Dpkg, "remove and purge" do
  before(:each) do
    @node = mock("Chef::Node", :null_object => true)
    @new_resource = mock("Chef::Resource::Package", 
      :null_object => true,
      :name => "wget",
      :version => nil,
      :package_name => "wget",
      :updated => nil,
      :options => nil
    )
    @provider = Chef::Provider::Package::Dpkg.new(@node, @new_resource)
  end

  it "should run dpkg -r to remove the package" do
    @provider.should_receive(:run_command_with_systems_locale).with({
      :command => "dpkg -r wget",
      :environment => {
        "DEBIAN_FRONTEND" => "noninteractive"
      }
    })
    @provider.remove_package("wget", "1.11.4-1ubuntu1")
  end

  it "should run dpkg -r to remove the package with options if specified" do
    @provider.should_receive(:run_command_with_systems_locale).with({
      :command => "dpkg -r --force-yes wget",
      :environment => {
        "DEBIAN_FRONTEND" => "noninteractive"
      }
    })
    @new_resource.stub!(:options).and_return("--force-yes")

    @provider.remove_package("wget", "1.11.4-1ubuntu1")
  end

  it "should run dpkg -P to purge the package" do
    @provider.should_receive(:run_command_with_systems_locale).with({
      :command => "dpkg -P wget",
      :environment => {
        "DEBIAN_FRONTEND" => "noninteractive"
      }
    })
    @provider.purge_package("wget", "1.11.4-1ubuntu1")
  end

  it "should run dpkg -P to purge the package with options if specified" do
    @provider.should_receive(:run_command_with_systems_locale).with({
      :command => "dpkg -P --force-yes wget",
      :environment => {
        "DEBIAN_FRONTEND" => "noninteractive"
      }
    })
    @new_resource.stub!(:options).and_return("--force-yes")

    @provider.purge_package("wget", "1.11.4-1ubuntu1")
  end
end

