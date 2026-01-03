#!/usr/bin/env ruby
require 'rubyripper/secureRip'

describe SecureRip do
  let(:log) {double('Log').as_null_object}
  let(:exec) {double('Execute').as_null_object}
  let(:deps) {double('Dependency').as_null_object}
  let(:disc) {double('Disc').as_null_object}
  let(:fileScheme) {double('FileScheme').as_null_object}
  let(:encoding) {double('Encode').as_null_object}
  let(:prefs) {double('Preferences').as_null_object}
  let(:track_selection) {[1, 2]}
  
  subject {SecureRip.new(track_selection, disc, fileScheme, log, encoding, deps, exec, prefs)}

  before do
    allow(prefs).to receive(:rippersettings).and_return('')
    allow(prefs).to receive(:offset).and_return(0)
    allow(prefs).to receive(:debug).and_return(false)
    allow(prefs).to receive(:image).and_return(false)
    allow(prefs).to receive(:padMissingSamples).and_return(false)
    allow(prefs).to receive(:cdrom).and_return('/dev/cdrom')
    allow(prefs).to receive(:maxThreads).and_return(0) # Disable cooldown logic
    
    allow(disc).to receive(:getStartSector).and_return(0)
    allow(disc).to receive(:getLengthSector).and_return(1000)
    allow(disc).to receive(:multipleDriveSupport).and_return(true)
    allow(disc).to receive(:audiotracks).and_return(10)
    
    allow(fileScheme).to receive(:getTempFile).and_return('/tmp/test.wav')
    
    allow(subject).to receive(:getCRC).and_return('00000000')
    allow(subject).to receive(:analyzeFiles) # Skip analysis
    allow(subject).to receive(:fileCreated).and_return(true) 
    allow(subject).to receive(:testFileSize).and_return(true)
    
    allow(deps).to receive(:cdparanoia_executable).and_return('cd-paranoia')
  end

  context "when ripping a track" do
    it "launches cd-paranoia command" do
      # We check that the command starts with cd-paranoia
      expect(exec).to receive(:launch).with(/^cd-paranoia/)
      subject.send(:rip, 1)
    end

    it "includes configured offset in command" do
      allow(prefs).to receive(:offset).and_return(6)
      
      # Expect -O 6 in the command
      expect(exec).to receive(:launch).with(/ -O 6 /)
      subject.send(:rip, 1)
    end
    
    it "includes cdrom device if multiple drive support is active" do
      allow(disc).to receive(:multipleDriveSupport).and_return(true)
      expect(exec).to receive(:launch).with(/ -d \/dev\/cdrom/)
      subject.send(:rip, 1)
    end
  end
end
