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

require 'rubyripper/accurateRip'
require 'tempfile'

describe AccurateRipResult do
  describe '#initialize' do
    it 'should initialize with default values' do
      result = AccurateRipResult.new
      expect(result.status).to eq(false)
      expect(result.computed_v1).to eq({})
      expect(result.computed_v2).to eq({})
      expect(result.pressings).to eq([])
      expect(result.track_results).to eq({})
    end
  end

  describe '#setComputedChecksums' do
    it 'should set computed checksums for a track' do
      result = AccurateRipResult.new
      result.setComputedChecksums(1, 0x12345678, 0x87654321)
      expect(result.computed_v1[1]).to eq(0x12345678)
      expect(result.computed_v2[1]).to eq(0x87654321)
    end
  end

  describe '#addPressing' do
    it 'should add pressing data' do
      result = AccurateRipResult.new
      pressing = { tracks: { 1 => { confidence: 5, crc: 0xABCDEF00 } } }
      result.addPressing(pressing)
      expect(result.pressings.size).to eq(1)
      expect(result.pressings[0][:tracks][1][:crc]).to eq(0xABCDEF00)
    end
  end

  describe '#setTrackResult' do
    it 'should set verification result for a track' do
      result = AccurateRipResult.new
      result.setTrackResult(1, true, :v2, 0, 10)
      expect(result.track_results[1][:matched]).to eq(true)
      expect(result.track_results[1][:version]).to eq(:v2)
      expect(result.track_results[1][:confidence]).to eq(10)
    end
  end

  describe '#finalize' do
    it 'should set status to true if all tracks matched' do
      result = AccurateRipResult.new
      result.setTrackResult(1, true, :v2, 0, 10)
      result.setTrackResult(2, true, :v1, 0, 5)
      result.finalize
      expect(result.status).to eq(true)
    end

    it 'should set status to false if any track mismatched' do
      result = AccurateRipResult.new
      result.setTrackResult(1, true, :v2, 0, 10)
      result.setTrackResult(2, false, nil, nil, nil)
      result.finalize
      expect(result.status).to eq(false)
    end
  end

  describe '#toStr' do
    it 'should return an appropriate message when no pressing data exists' do
      result = AccurateRipResult.new
      output = result.toStr
      expect(output).to include('No entry found in the database')
    end

    it 'should return a string containing match results' do
      result = AccurateRipResult.new
      result.addPressing({ tracks: { 1 => { confidence: 5, crc: 0x12345678 } } })
      result.setComputedChecksums(1, 0x12345678, 0x87654321)
      result.setTrackResult(1, true, :v1, 0, 5)
      result.finalize
      output = result.toStr
      expect(output).to include('Matched')
      expect(output).to include('12345678(5)')
    end
  end
end

describe AccurateRip do
  let(:disc) { double('Disc').as_null_object }
  let(:prefs) { double('Preferences').as_null_object }

  before(:each) do
    allow(prefs).to receive(:debug).and_return(false)
    allow(disc).to receive(:audiotracks).and_return(10)
    allow(disc).to receive(:freedbDiscid).and_return('7F087C0A')

    # Mock track start positions
    start_sectors = { 1 => 0, 2 => 13209, 3 => 36539, 4 => 53497, 5 => 68172,
                      6 => 81097, 7 => 87182, 8 => 106732, 9 => 122218, 10 => 124080 }
    start_sectors.each do |track, sector|
      allow(disc).to receive(:getStartSector).with(track).and_return(sector)
    end
    allow(disc).to receive(:getLengthSector).with(10).and_return(38839)
  end

  describe '#initialize' do
    it 'should initialize with disc and prefs' do
      ar = AccurateRip.new(disc, prefs)
      expect(ar).to be_a(AccurateRip)
    end
  end

  describe 'CRC calculation' do
    let(:ar) { AccurateRip.new(disc, prefs) }

    it 'should calculate V1 CRC' do
      # Simple test data: 8 bytes (2 DWORD)
      audio_data = [0x12345678, 0x9ABCDEF0].pack('V*')
      # Set track count to 3 (use middle track to avoid skipping sectors 1/last)
      allow(disc).to receive(:audiotracks).and_return(3)
      v1_crc = ar.send(:computeV1Checksum, 2, audio_data)
      expect(v1_crc).to be_a(Integer)
    end

    it 'should calculate V2 CRC' do
      audio_data = [0x12345678, 0x9ABCDEF0].pack('V*')
      allow(disc).to receive(:audiotracks).and_return(3)
      v2_crc = ar.send(:computeV2Checksum, 2, audio_data)
      expect(v2_crc).to be_a(Integer)
    end
  end

  describe 'Disc Identifier construction' do
    it 'should construct Disc Identifier correctly' do
      ar = AccurateRip.new(disc, prefs)
      ar.send(:buildDiscIdent)
      disc_ident = ar.instance_variable_get(:@disc_ident)

      expect(disc_ident[:track_count]).to eq(10)
      # TrackOffsetsAdded should be calculated
      expect(disc_ident[:track_offsets_added]).to be > 0
      # TrackOffsetsMultiplied should be calculated
      expect(disc_ident[:track_offsets_multiplied]).to be > 0
      # FreeDBID should be set
      expect(disc_ident[:freedb_id]).to eq(0x7F087C0A)
    end
  end

  describe 'bin file parsing' do
    it 'should parse bin data correctly' do
      ar = AccurateRip.new(disc, prefs)
      result = AccurateRipResult.new

      # Create sample bin data: DiscIdent (13 bytes) + Track (9 bytes x 2)
      bin_data = ""
      # DiscIdent: track_count=2, offsets_added, offsets_multiplied, freedb_id (4 bytes each LE)
      bin_data += [2].pack('C')  # track_count (1 byte)
      bin_data += [1000].pack('V')  # track_offsets_added (4 bytes)
      bin_data += [2000].pack('V')  # track_offsets_multiplied (4 bytes)
      bin_data += [0x12345678].pack('V')  # freedb_id (4 bytes)
      # Track 1: confidence=5, crc=0x12345678, offset_find_crc=0
      bin_data += [5].pack('C')
      bin_data += [0x12345678].pack('V')
      bin_data += [0].pack('V')
      # Track 2: confidence=3, crc=0xABCDEF00, offset_find_crc=0
      bin_data += [3].pack('C')
      bin_data += [0xABCDEF00].pack('V')
      bin_data += [0].pack('V')

      temp_file = Tempfile.new(['test_accuraterip', '.bin'])
      temp_file.binmode
      temp_file.write(bin_data)
      temp_file.close

      ar.send(:parseAccurateRipData, temp_file.path, result)
      temp_file.unlink

      expect(result.pressings.size).to eq(1)
      expect(result.pressings[0][:tracks][1][:confidence]).to eq(5)
      expect(result.pressings[0][:tracks][1][:crc]).to eq(0x12345678)
      expect(result.pressings[0][:tracks][2][:confidence]).to eq(3)
      expect(result.pressings[0][:tracks][2][:crc]).to eq(0xABCDEF00)
    end
  end
end
