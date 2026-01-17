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

require 'rubyripper/disc/scanDiscCdparanoia'

describe ScanDiscCdparanoia do

  def setQueryReply(reply, command=nil)
    allow(prefs).to receive('testdisc').and_return false
    command ||= 'cd-paranoia -d /dev/cdrom -vQ'
    allow(exec).to receive(:launch).with(command).and_return reply
  end

  let(:exec) {double('Execute').as_null_object}
  let(:perm) {double('PermissionDrive').as_null_object}
  let(:prefs) {double('Preferences').as_null_object}
  let(:disc) {ScanDiscCdparanoia.new(exec, perm, prefs)}

  context "Before scanning any disc" do
    it "shouldn't set default values" do
      expect(disc.status).to eq(nil)
      expect(disc.playtime).to eq(nil)
      expect(disc.audiotracks).to eq(nil)
      expect(disc.devicename).to eq(nil)
      expect(disc.firstAudioTrack).to eq(nil)
    end

    it "should raise an error when a function other than scan() is called" do
      expect{disc.getStartSector(1)}.to raise_error(RuntimeError, /getStartSector/)
      expect{disc.getLengthSector(1)}.to raise_exception(RuntimeError, /getLengthSector/)
      expect{disc.getLengthText(1)}.to raise_exception(RuntimeError, /getLengthText/)
      expect{disc.getFileSize(1)}.to raise_exception(RuntimeError, /getFileSize/)
      expect{disc.getStartSector('image')}.to raise_exception(RuntimeError, /getStartSector/)
      expect{disc.getLengthSector('image')}.to raise_exception(RuntimeError, /getLengthSector/)
      expect{disc.getLengthText('image')}.to raise_exception(RuntimeError, /getLengthText/)
      expect{disc.getFileSize('image')}.to raise_exception(RuntimeError, /getFileSize/)
    end
  end

  context "When trying to scan a disc" do
    before(:each) do
      expect(prefs).to receive(:cdrom).at_least(:once).and_return('/dev/cdrom')
      expect(perm).to receive(:problems?).once.and_return(false)
    end

    it "should abort when cdparanoia is not installed" do
      setQueryReply(nil)
      disc.scan()
      expect(disc.status).to eq('error')
      expect(disc.error).to eq([:notInstalled, 'cd-paranoia'])
    end
    
    it "should abort when cdparanoia is unable to open the disc" do
      setQueryReply(["Unable to open disc.  Is there an audio CD in the drive?"])
      disc.scan()
      expect(disc.status).to eq('error')
      expect(disc.error).to eq([:noDiscInDrive, '/dev/cdrom'])
    end

    it "should have one retry without the drive parameter when cdparanoia doesn't recognize it"  do
      setQueryReply(["USAGE:"])
      setQueryReply(["USAGE:"], 'cd-paranoia -vQ')
      disc.scan()
      expect(disc.status).to eq('error')
      expect(disc.error).to eq([:wrongParameters, 'cd-paranoia'])
    end

    it "should abort when the disc drive is not found" do
      setQueryReply(["Could not stat /dev/cdrom: No such file or directory"])
      disc.scan()
      expect(disc.status).to eq('error')
      expect(disc.error).to eq([:unknownDrive, '/dev/cdrom'])
    end
  end

  context "When a disc is found (legacy format)" do
    before(:each) do
      @cdparanoia ||= File.read('spec/disc/data/cdparanoia').split("\n")
      expect(perm).to receive(:problems?).once.and_return(false)
      expect(perm).to receive(:problemsSCSI?).once.and_return(false)
      expect(prefs).to receive(:cdrom).at_least(:once).and_return('/dev/cdrom')
    end

    it "should set the status to ok" do
      setQueryReply(@cdparanoia)
      disc.scan()
      expect(disc.status).to eq('ok')
    end

    it "should save the playtime in minutes:seconds" do
      setQueryReply(@cdparanoia)
      disc.scan()
      expect(disc.playtime).to eq('36:12')
    end

    it "should save the amount of audiotracks" do
      setQueryReply(@cdparanoia)
      disc.scan()
      expect(disc.audiotracks).to eq(10)
    end

    it "should detect the devicename" do
      setQueryReply(@cdparanoia)
      disc.scan()
      expect(disc.devicename).to eq('HL-DT-ST DVDRAM GH22NS40 NL01')
    end

    it "should detect the first track" do
      setQueryReply(@cdparanoia)
      disc.scan()
      expect(disc.firstAudioTrack).to eq(1)
    end

    it "should return the startsector for a track" do
      setQueryReply(@cdparanoia)
      disc.scan()
      expect(disc.getStartSector(0)).to eq(nil)
      expect(disc.getStartSector(1)).to eq(0)
      expect(disc.getStartSector(10)).to eq(124080)
      expect(disc.getStartSector(11)).to eq(nil)
    end

    it "should return the amount of sectors for a track" do
      setQueryReply(@cdparanoia)
      disc.scan()
      expect(disc.getLengthSector(0)).to eq(nil)
      expect(disc.getLengthSector(1)).to eq(13209)
      expect(disc.getLengthSector(10)).to eq(38839)
      expect(disc.getLengthSector(11)).to eq(nil)
    end

    it "should return the length in mm:ss for a track" do
      setQueryReply(@cdparanoia)
      disc.scan()
      expect(disc.getLengthText(0)).to eq(nil)
      expect(disc.getLengthText(1)).to eq('02:56')
      expect(disc.getLengthText(10)).to eq('08:37')
      expect(disc.getLengthText(11)).to eq(nil)
    end

    it "should return the filesize in bytes for a track" do
      setQueryReply(@cdparanoia)
      disc.scan()
      expect(disc.getFileSize(0)).to eq(nil)
      expect(disc.getFileSize(1)).to eq(31067612)
      expect(disc.getFileSize(10)).to eq(91349372)
      expect(disc.getFileSize(11)).to eq(nil)
    end
    
    it "should serve image ripping as well" do
      setQueryReply(@cdparanoia)
      disc.scan()
      expect(disc.getStartSector(nil)).to eq(0)
      expect(disc.getLengthSector(nil)).to eq(162919)
      expect(disc.getLengthText(nil)).to eq('36:12')
      expect(disc.getFileSize(nil)).to eq(383185532)
    end

    it "should detect the total sectors of the disc" do
      setQueryReply(@cdparanoia)
      disc.scan()
      expect(disc.totalSectors).to eq(162919)
    end
  end

  context "When a disc is found (libcdio format)" do
    before(:each) do
      @libcdio ||= File.read('spec/disc/data/cdparanoia_libcdio').split("\n")
      expect(perm).to receive(:problems?).once.and_return(false)
      expect(perm).to receive(:problemsSCSI?).once.and_return(false)
      expect(prefs).to receive(:cdrom).at_least(:once).and_return('/dev/cdrom')
    end

    it "should set the status to ok" do
      setQueryReply(@libcdio)
      disc.scan()
      expect(disc.status).to eq('ok')
    end

    it "should save the playtime" do
      setQueryReply(@libcdio)
      disc.scan()
      expect(disc.playtime).to eq('36:12')
    end

    it "should save the amount of audiotracks" do
      setQueryReply(@libcdio)
      disc.scan()
      expect(disc.audiotracks).to eq(10)
    end

    it "should return the startsector for a track" do
      setQueryReply(@libcdio)
      disc.scan()
      expect(disc.getStartSector(1)).to eq(0)
      expect(disc.getStartSector(10)).to eq(124080)
    end

    it "should return the amount of sectors for a track" do
      setQueryReply(@libcdio)
      disc.scan()
      expect(disc.getLengthSector(1)).to eq(13209)
      expect(disc.getLengthSector(10)).to eq(38839)
    end

    it "should detect the total sectors of the disc" do
      setQueryReply(@libcdio)
      disc.scan()
      expect(disc.totalSectors).to eq(162919)
    end
  end
end
