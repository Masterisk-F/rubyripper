#!/usr/bin/env ruby
#    Rubyripper - A secure ripper for Linux/BSD/OSX
#    Copyright (C) 2007 - 2010 Bouke Woudstra (boukewoudstra@gmail.com)
#
#    This file is part of Rubyripper. Rubyripper is free software: you can
#    redistribute it and/or modify it under the terms of the GNU General
#    Public License as published by the Free Software Foundation, either
#    version 3 of the License, or (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>

require 'rubyripper/system/dependency'

describe Dependency do
  let(:file) {double('File').as_null_object}
  before(:each) {allow(file).to receive("exist?").and_return(false)}
    
  context "When searching for the disc drive on freebsd" do
    let(:deps) {Dependency.new(file, platform='freebsd')}
    
    it "should query the device on /dev/cd# for existence" do
      (0..9).each{|num| expect(file).to receive("exist?").with("/dev/cd#{num}").and_return(false)}
      expect(deps.cdrom()).to eq("unknown")
    end
    
    it "should query the device on /dev/acd# for existence" do
      (0..9).each{|num| expect(file).to receive("exist?").with("/dev/acd#{num}").and_return(false)}
      expect(deps.cdrom()).to eq("unknown")
    end
    
    it "should detect a drive on /dev/cd0" do
      expect(file).to receive("exist?").with("/dev/cd0").and_return(true)   
      expect(deps.cdrom()).to eq('/dev/cd0')
    end
    
    it "should detect a drive on /dev/cd9" do
      expect(file).to receive("exist?").with("/dev/cd9").and_return(true)
      expect(deps.cdrom()).to eq('/dev/cd9')
    end
    
    it "should detect a drive on /dev/acd0" do
      expect(file).to receive("exist?").with("/dev/acd0").and_return(true)
      expect(deps.cdrom()).to eq('/dev/acd0')
    end
    
    it "should detect a drive on /dev/acd9" do
      expect(file).to receive("exist?").with("/dev/acd9").and_return(true)
      expect(deps.cdrom()).to eq('/dev/acd9')
    end
  end
  
  context "When searching for the disc drive on linux" do
    let(:deps) {Dependency.new(file, platform='linux')}
    
    it "should detect a drive on /dev/cdrom" do
      expect(file).to receive("exist?").with("/dev/cdrom").and_return(true)   
      expect(deps.cdrom()).to eq('/dev/cdrom')
    end
    
    it "should detect a drive on /dev/dvdrom" do
      expect(file).to receive("exist?").with("/dev/dvdrom").and_return(true)   
      expect(deps.cdrom()).to eq('/dev/dvdrom')
    end
    
    it "should query the device on /dev/sr# for existence" do
      (0..9).each{|num| expect(file).to receive("exist?").with("/dev/sr#{num}").and_return(false)}
      expect(deps.cdrom()).to eq("unknown")
    end
    
    it "should detect a drive on /dev/sr0" do
      expect(file).to receive("exist?").with("/dev/sr0").and_return(true)   
      expect(deps.cdrom()).to eq('/dev/sr0')
    end
    
    it "should detect a drive on /dev/sr9" do
      expect(file).to receive("exist?").with("/dev/sr9").and_return(true)   
      expect(deps.cdrom()).to eq('/dev/sr9')
    end
  end
  context "When checking for forced dependencies" do
    let(:deps) {Dependency.new(file, platform='linux')}

    it "should return true when cd-paranoia is found" do
      expect(deps).to receive(:installed?).with('cd-paranoia').and_return(true)
      deps.send(:checkForcedDeps)
      deps.instance_variable_set(:@deps, Hash[deps.instance_variable_get(:@forcedDeps)])
      expect(deps.send(:forceDepsRuntime)).to eq(nil) # Should not raise or exit
    end

    it "should abort when cd-paranoia is not installed" do
      expect(deps).to receive(:installed?).with('cd-paranoia').and_return(false)
      deps.send(:checkForcedDeps)
      deps.instance_variable_set(:@deps, Hash[deps.instance_variable_get(:@forcedDeps)])
      expect{deps.send(:forceDepsRuntime)}.to raise_error(SystemExit)
    end
    
    it "should abort when only legacy cdparanoia is installed (strict migration)" do
      # Mocking cd-paranoia missing
      expect(deps).to receive(:installed?).with('cd-paranoia').and_return(false)
      # We don't check for legacy anymore, so this test just confirms failures when cd-paranoia is missing
      
      deps.send(:checkForcedDeps)
      deps.instance_variable_set(:@deps, Hash[deps.instance_variable_get(:@forcedDeps)])
      expect{deps.send(:forceDepsRuntime)}.to raise_error(SystemExit)
    end
  end
end
